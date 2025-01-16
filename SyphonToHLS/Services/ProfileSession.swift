import AVFoundation
import CoreImage
import Dependencies
import Metal
import Observation
import OSLog
import SimplyCoreAudio

@MainActor
@Observable
final class ProfileSession {
	@ObservationIgnored
	@Dependency(\.configManager) private var configManager

	private var webServer: WebServer?

	let scheduleManager = ScheduleManager()

	let device = MTLCreateSystemDefaultDevice()!

	let syphonService = SyphonService()
	let audioSourceService = AudioSourceService()
	let audioOutputService = AudioOutputService.shared
	let captureSession = AVCaptureSession()
	let previewOutput = AVCaptureAudioPreviewOutput()

	var baseURL = URL.moviesDirectory
		.appendingPathComponent("Recordings")
	var url: URL?

	private let logger = Logger(category: "ProfileSession")

	var qualityLevels: Set<VideoQualityLevel> {
		configManager.config.encoder.qualityLevels
	}

	var syphonServer: ServerDescription? {
		guard let syphonServerID = configManager.config.videoSource?.syphonID else { return nil }
		return syphonService.servers.first(where: { $0.id == syphonServerID })
	}

	private final class FrameSourceManager: FrameSource {
		let videoSource: VideoSource
		let frameSource: any FrameSource

		init(videoSource: VideoSource, frameSource: any FrameSource) {
			self.videoSource = videoSource
			self.frameSource = frameSource
		}

		var frames: any AsyncSequence<Frame, Never> {
			frameSource.frames
		}
	}

	@ObservationIgnored
	private weak var _frameSource: FrameSourceManager?
	var frameSource: (any FrameSource)? {
		guard let videoSource = configManager.config.videoSource else { return nil }

		if let manager = _frameSource, manager.videoSource == videoSource {
			return manager.frameSource
		}

		switch videoSource {
		case let .syphon(id: id):
			if let syphonServer = syphonService.servers.first(where: { $0.id == id }) {
				let syphonClient = SyphonCoreImageClient(syphonServer, device: self.device)

				let frameSource = FrameSourceManager(videoSource: videoSource, frameSource: syphonClient)

				_frameSource = frameSource
				return frameSource
			} else {
				return nil
			}
		case let .ndi(name: name):
			let player = NDIPlayer(name: name)

			let frameSource = FrameSourceManager(
				videoSource: videoSource,
				frameSource: NDIFrameSource(player: player)
			)

			_frameSource = frameSource
			return frameSource
		}
	}

	var audioDevice: AVCaptureDevice? {
		get {
			// by looking in audioSourceService, we will trigger an observation update if something becomes available
			audioSourceService.devices.first(where: { $0.uniqueID == configManager.config.audioDeviceID }) ??
				AVCaptureDevice(uniqueID: configManager.config.audioDeviceID)
		}
		set {
			configManager.config.audioDeviceID = newValue?.uniqueID ?? ""
		}
	}

	var monitorDeviceUID: String {
		get {
			configManager.config.monitorDeviceID
		}
		set {
			configManager.config.monitorDeviceID = newValue
		}
	}

	var isRunning = false {
		didSet {
			if isRunning {
				self.url = self.baseURL.appending(component: Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))
			} else {
				self.url = nil
			}
		}
	}

	static let liveValue = ProfileSession()

	init() {}

	func setup() async {
		print("url", baseURL.path())
		guard await AVCaptureDevice.requestAccess(for: .audio) else { return }

		self.trackAudioInput()

		previewOutput.volume = 1
		self.trackPreview()

		captureSession.startRunning()

		writeVariantPlaylist()
		trackVideoRecording()
		trackAudioRecording()
		trackSchedule()
		trackWebServer()
	}

	func start() {
		self.isRunning = true
	}

	func stop() {
		self.isRunning = false
	}

	private func trackSchedule() {
		let isActive = withObservationTracking {
			scheduleManager.isActive
		} onChanged: { [weak self] in
			self?.trackScheduleChange()
		}

		if isActive {
			self.isRunning = true
		}
	}

	private func trackScheduleChange() {
		self.isRunning = withObservationTracking {
			scheduleManager.isActive
		} onChanged: { [weak self] in
			self?.trackScheduleChange()
		}
	}

	private func writeVariantPlaylist() {
		withObservationTracking {
			guard self.isRunning else { return }

			let uploader = S3Uploader(configManager.config.aws)

			let variantPlaylist =
				"""
				#EXTM3U
				#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="en",NAME="English",AUTOSELECT=YES, DEFAULT=YES,URI="audio/live.m3u8"


				""" +
				qualityLevels.map {
					"""
					#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=\($0.bitrate),RESOLUTION=\(Int($0.resolutions.width))x\(Int($0.resolutions.height)),CODECS="avc1.4d401e",AUDIO="audio"
					\($0.name)/live.m3u8
					"""
				}.joined(separator: "\n")

			if let url {
				Task {
					do {
						let playlistURL = url.appendingPathComponent("live.m3u8")
						try variantPlaylist.write(to: playlistURL, atomically: true, encoding: .utf8)
					} catch {
						self.logger.error("failed to write variant playlist to file \(error)")
					}
				}
			}

			Task {
				do {
					try await uploader.write(
						data: .init(variantPlaylist.utf8),
						key: "live.m3u8",
						type: .m3uPlaylist,
						shouldEnableCaching: false
					)
				} catch {
					self.logger.error("failed to write variant playlist to s3 \(error)")
				}
			}
		} onChanged: { [weak self] in
			self?.writeVariantPlaylist()
		}
	}

	private var videoTask: Task<Void, Never>?
	private func trackVideoRecording() {
		withObservationTracking { [logger] in
			let preferredOutputSegmentInterval = configManager.config.encoder.preferredOutputSegmentInterval

			videoTask?.cancel()

			guard
				let url,
				let frameSource = self.frameSource
			else { return }

			let uploader = S3Uploader(configManager.config.aws)

			let qualityLevels = self.qualityLevels

			videoTask = Task {
				await withTaskGroup(of: Void.self) { group in
					for quality in qualityLevels {
						group.addTask {
							while !Task.isCancelled {
								let videoService = HLSVideoService(
									preferredOutputSegmentInterval: preferredOutputSegmentInterval,
									url: url,
									frameSource: frameSource,
									uploader: uploader,
									quality: quality
								)

								do {
									try await videoService.start()
								} catch {
									logger.error("hls session failed: \(error)")
								}

								try? await Task.sleep(for: .seconds(1))
							}
						}
					}

					await group.waitForAll()
				}
			}
		} onChanged: { [weak self] in
			self?.trackVideoRecording()
		}
	}

	private var audioService: HLSAudioService?
	private func trackAudioRecording() {
		withObservationTracking {
			if self.isRunning, let audioDevice, let url {
				let preferredOutputSegmentInterval = configManager.config.encoder.preferredOutputSegmentInterval

				audioService?.stop()

				audioService = HLSAudioService(
					preferredOutputSegmentInterval: preferredOutputSegmentInterval,
					url: url,
					audioDevice: audioDevice,
					captureSession: captureSession,
					uploader: S3Uploader(configManager.config.aws)
				)
				audioService?.start()
			} else {
				audioService?.stop()
				audioService = nil
			}
		} onChanged: { [weak self] in
			self?.trackAudioRecording()
		}
	}

	private func trackPreview() {
		withObservationTracking {
			captureSession.beginConfiguration()

			if audioOutputService.devices.contains(where: { $0.uid == monitorDeviceUID }) {
				previewOutput.outputDeviceUniqueID = monitorDeviceUID

				if !captureSession.outputs.contains(previewOutput), captureSession.canAddOutput(previewOutput) {
					captureSession.addOutput(previewOutput)
				}
			} else {
				captureSession.removeOutput(previewOutput)
			}

			captureSession.commitConfiguration()
		} onChanged: { [weak self] in
			self?.trackPreview()
		}
	}

	private var captureDeviceInput: AVCaptureDeviceInput?
	private func trackAudioInput() {
		withObservationTracking {
			guard captureDeviceInput?.device != self.audioDevice else { return }

			captureSession.beginConfiguration()

			if let captureDeviceInput {
				captureSession.removeInput(captureDeviceInput)
			}

			if let audioDevice {
				do {
					let captureDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
					if captureSession.canAddInput(captureDeviceInput) {
						captureSession.addInput(captureDeviceInput)
					}
					self.captureDeviceInput = captureDeviceInput
				} catch {
					logger.error("failed to setup audio input: \(error)")
				}
			}

			captureSession.commitConfiguration()
		} onChanged: { [weak self] in
			self?.trackAudioInput()
		}
	}

	private func trackWebServer() {
		let url = withObservationTracking {
			self.url
		} onChanged: { [weak self] in
			self?.trackWebServer()
		}

		guard let url else { return }

		if let webServer {
			Task { await webServer.stop() }
		}

		let webServer = WebServer(directory: url)
		self.webServer = webServer
		Task { await webServer.start() }
	}
}
