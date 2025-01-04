import AVFoundation
import CoreImage
import Dependencies
import Metal
import Observation
import OSLog
import SimplyCoreAudio

extension AppStorageKey where Value == String {
	static let syphonServerName = AppStorageKey(key: "syphonServerName")
	static let syphonServerApp = AppStorageKey(key: "syphonServerApp")
	static let audioDeviceID = AppStorageKey(key: "audioDeviceID")
	static let monitorDeviceID = AppStorageKey(key: "monitorDeviceID")
}

@MainActor
@Observable
final class ProfileSession {
	@ObservationIgnored
	@Dependency(\.configManager) private var configManager

	let scheduleManager = ScheduleManager()

	let appStorage = AppStorage.shared

	let device = MTLCreateSystemDefaultDevice()!

	let syphonService = SyphonService()
	let audioSourceService = AudioSourceService.shared
	let audioOutputService = AudioOutputService.shared
	let captureSession = AVCaptureSession()
	let previewOutput = AVCaptureAudioPreviewOutput()

	var image: CIImage?

	var baseURL = URL.moviesDirectory
		.appendingPathComponent("Recordings")
	var url: URL?

	private let logger = Logger(category: "ProfileSession")

	let qualityLevels = [VideoQualityLevel.high]

	var syphonServerID: ServerDescription.ID? {
		get {
			let name = appStorage[.syphonServerName]
			let appName = appStorage[.syphonServerApp]
			guard !name.isEmpty, !appName.isEmpty else { return nil }

			return ServerDescription.ID(appName: appName, name: name)
		}
		set {
			appStorage[.syphonServerName] = newValue?.name ?? ""
			appStorage[.syphonServerApp] = newValue?.appName ?? ""
		}
	}

	var syphonServer: ServerDescription? {
		guard let syphonServerID else { return nil }
		return syphonService.servers.first(where: { $0.id == syphonServerID })
	}

	var audioDevice: AVCaptureDevice? {
		get {
			// by looking in audioSourceService, we will trigger an observation update if something becomes available
			audioSourceService.devices.first(where: { $0.uniqueID == appStorage[.audioDeviceID] }) ??
				AVCaptureDevice(uniqueID: appStorage[.audioDeviceID])
		}
		set {
			appStorage[.audioDeviceID] = newValue?.uniqueID ?? ""
		}
	}

	var monitorDeviceUID: String {
		get {
			appStorage[.monitorDeviceID]
		}
		set {
			appStorage[.monitorDeviceID] = newValue
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

	nonisolated
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
		withObservationTracking { [weak self] in
			guard let self else { return }

			guard self.isRunning else { return }

			let uploader = S3Uploader(appStorage: self.appStorage)

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
		}
	}

	private var videoTask: Task<Void, Never>?
	private func trackVideoRecording() {
		withObservationTracking { [weak self, logger, qualityLevels] in
			guard let self else { return }

			videoTask?.cancel()

			guard
				let url,
				let client = syphonServer.map({
					SyphonCoreImageClient($0, device: self.device)
				})
			else { return }

			let uploader = S3Uploader(appStorage: self.appStorage)

			videoTask = Task {
				await withTaskGroup(of: Void.self) { group in
					for quality in qualityLevels {
						group.addTask {
							while !Task.isCancelled {
								let videoService = HLSVideoService(
									url: url,
									syphonClient: client,
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
		}
	}

	private var audioService: HLSAudioService?
	private func trackAudioRecording() {
		withObservationTracking {
			if self.isRunning, let audioDevice, let url {
				audioService?.stop()

				audioService = HLSAudioService(
					url: url,
					audioDevice: audioDevice,
					captureSession: captureSession,
					uploader: S3Uploader(appStorage: self.appStorage)
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
}

extension ProfileSession: DependencyKey {
	nonisolated
	static let liveValue = ProfileSession()
}

extension DependencyValues {
	var profileSession: ProfileSession {
		get { self[ProfileSession.self] }
		set { self[ProfileSession.self] = newValue }
	}
}
