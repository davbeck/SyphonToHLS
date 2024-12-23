import AVFoundation
import CoreImage
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

extension AppStorageKey where Value == Bool {
	static let isRunning = AppStorageKey(key: "isRunning")
}

@MainActor
@Observable
final class ProfileSession {
	let appStorage = AppStorage.shared

	let device = MTLCreateSystemDefaultDevice()!

	let syphonService = SyphonService()
	let audioSourceService = AudioSourceService.shared
	let audioOutputService = AudioOutputService.shared
	let captureSession = AVCaptureSession()
	let previewOutput = AVCaptureAudioPreviewOutput()

	var image: CIImage?

	var url = URL.moviesDirectory
		.appendingPathComponent("Recordings")

	private let logger = Logger(category: "ProfileSession")

	static let shared = ProfileSession()

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

	var isRunning = false

	func start() async {
		print("url", url.path())
		guard await AVCaptureDevice.requestAccess(for: .audio) else { return }

		self.updateAudioInput()

		previewOutput.volume = 1
		self.updatePreview()

		captureSession.startRunning()

		var currentTask: Task<Void, Never>?
		let currentServer = AsyncStream.makeObservationStream {
			(self.appStorage[.isRunning], self.syphonServer, self.audioDevice, S3Uploader(appStorage: self.appStorage))
		}
		for await (isRunning, syphonServer, audioDevice, uploader) in currentServer {
			print("isRunning", isRunning)
			currentTask?.cancel()

			guard isRunning else { continue }

			currentTask = Task {
				await self.start(syphonServer: syphonServer, audioDevice: audioDevice, uploader: uploader)
			}
		}
	}

	func start(syphonServer: ServerDescription?, audioDevice: AVCaptureDevice?, uploader: S3Uploader) async {
		isRunning = true
		defer { isRunning = false }

		guard syphonServer != nil || audioDevice != nil else { return }

		let url = self.url.appending(component: Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))

		let client = syphonServer.map {
			SyphonCoreImageClient($0, device: device)
		}

		let qualityLevels = VideoQualityLevel.allCases

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

		await withTaskGroup(of: Void.self) { [logger, captureSession] group in
			group.addTask {
				do {
					try variantPlaylist.write(
						to: url.appending(component: "live.m3u8"),
						atomically: true,
						encoding: .utf8
					)
				} catch {
					logger.error("failed to write variant playlist to file \(error)")
				}
			}

			group.addTask {
				do {
					try await uploader.write(
						data: .init(variantPlaylist.utf8),
						key: "live.m3u8",
						type: .m3uPlaylist,
						shouldEnableCaching: false
					)
				} catch {
					logger.error("failed to write variant playlist to s3 \(error)")
				}
			}

			// audioDevice: audioDevice
			if let client {
				for quality in qualityLevels {
					group.addTask {
						while !Task.isCancelled {
							let videoService = HLSVideoService(url: url, syphonClient: client, uploader: uploader, quality: quality)
							do {
								try await videoService.start()
							} catch {
								logger.error("hls session failed: \(error)")
							}

							try? await Task.sleep(for: .seconds(1))
						}
					}
				}
			}

			if let audioDevice {
				group.addTask {
					while !Task.isCancelled {
						let audioService = HLSAudioService(
							url: url,
							audioDevice: audioDevice,
							captureSession: captureSession,
							uploader: uploader
						)
						do {
							try await audioService.start()
						} catch {
							logger.error("hls session failed: \(error)")
						}

						try? await Task.sleep(for: .seconds(1))
					}
				}
			}

			if let client {
				group.addTask { @MainActor in
					for await frame in client.frames {
						self.image = frame.image
					}
				}
			}

			await group.waitForAll()
		}
	}

	func updatePreview() {
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
		} onChange: { [weak self] in
			RunLoop.main.perform {
				MainActor.assumeIsolated {
					self?.updatePreview()
				}
			}
		}
	}

	private var captureDeviceInput: AVCaptureDeviceInput?
	func updateAudioInput() {
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
		} onChange: { [weak self] in
			RunLoop.main.perform {
				MainActor.assumeIsolated {
					self?.updatePreview()
				}
			}
		}
	}
}

extension AsyncStream {
	@MainActor
	static func makeObservationStream(_ apply: @escaping () -> Element) -> AsyncStream<Element> {
		let (stream, continuation) = AsyncStream.makeStream()
		func next() {
			continuation.yield(withObservationTracking {
				apply()
			} onChange: {
				RunLoop.main.perform {
					MainActor.assumeIsolated {
						next()
					}
				}
			})
		}

		next()

		return stream
	}
}
