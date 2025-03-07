import AVFoundation
import Combine
import CoreImage
import Dependencies
import Metal
import NDI
import Observation
import OSLog
import Sharing
import SimplyCoreAudio

@MainActor
@Observable
final class ProfileSession {
	@ObservationIgnored
	@Shared(.audioSource) private var audioSource

	@ObservationIgnored
	@Shared(.videoSource) private var videoSource

	@ObservationIgnored
	@Shared(.monitorDeviceID) private var monitorDeviceID

	@ObservationIgnored
	@Shared(.encoderConfig) private var encoderConfig

	@ObservationIgnored
	@Shared(.awsConfig) private var awsConfig

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
		encoderConfig.qualityLevels
	}

	private final class FrameSourceManager: VideoFrameSource {
		let videoSource: VideoSource
		let frameSource: any VideoFrameSource

		init(videoSource: VideoSource, frameSource: any VideoFrameSource) {
			self.videoSource = videoSource
			self.frameSource = frameSource
		}

		var frames: any AsyncSequence<VideoFrame, Never> {
			frameSource.frames
		}
	}

	@ObservationIgnored
	private weak var _frameSource: FrameSourceManager?
	var frameSource: (any VideoFrameSource)? {
		guard let videoSource else { return nil }

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
			let player = NDIPlayer.player(for: name)

			let frameSource = FrameSourceManager(
				videoSource: videoSource,
				frameSource: NDIVideoFrameSource(player: player)
			)

			_frameSource = frameSource
			return frameSource
		}
	}

	var audioDevice: AVCaptureDevice? {
		guard let audioDeviceID = audioSource?.audioDeviceID else { return nil }

		// by looking in audioSourceService, we will trigger an observation update if something becomes available
		return audioSourceService.device(withID: audioDeviceID)
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

			let uploader = S3Uploader(awsConfig)

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
			let preferredOutputSegmentInterval = encoderConfig.preferredOutputSegmentInterval

			videoTask?.cancel()

			guard
				let url,
				let frameSource = self.frameSource
			else { return }

			let uploader = S3Uploader(awsConfig)

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

	private var audioTask: AnyCancellable?
	private func trackAudioRecording() {
		withObservationTracking {
			guard self.isRunning, let url else {
				audioTask = nil
				return
			}

			let preferredOutputSegmentInterval = encoderConfig.preferredOutputSegmentInterval
			let uploader = S3Uploader(awsConfig)

			switch audioSource {
			case let .audioDevice(id: id):
				guard let audioDevice = self.audioDevice else {
					audioTask = nil
					break
				}

				let audioService = HLSAudioService(
					preferredOutputSegmentInterval: preferredOutputSegmentInterval,
					url: url,
					audioDevice: audioDevice,
					captureSession: captureSession,
					uploader: uploader
				)
				audioService.start()

				audioTask = AnyCancellable {
					audioService.stop()
				}
			case let .ndi(name: name):
				let player = NDIPlayer.player(for: name)

				let service = HLSNDIAudioService(
					preferredOutputSegmentInterval: preferredOutputSegmentInterval,
					player: player,
					url: url,
					uploader: uploader
				)

				let task = Task {
					await service.start()
				}
				audioTask = AnyCancellable {
					task.cancel()
				}
			case .none:
				audioTask = nil
			}
		} onChanged: { [weak self] in
			self?.trackAudioRecording()
		}
	}

	private func trackPreview() {
		withObservationTracking {
			captureSession.beginConfiguration()

			if audioOutputService.devices.contains(where: { $0.uid == monitorDeviceID }) {
				previewOutput.outputDeviceUniqueID = monitorDeviceID

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
