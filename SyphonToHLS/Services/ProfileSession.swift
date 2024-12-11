import AVFoundation
import CoreImage
import Metal
import Observation
import OSLog

extension AppStorageKey where Value == String {
	static let syphonServerName = AppStorageKey(key: "syphonServerName")
	static let syphonServerApp = AppStorageKey(key: "syphonServerApp")
	static let audioDeviceID = AppStorageKey(key: "audioDeviceID")
}

extension AppStorageKey where Value == Bool {
	static let isRunning = AppStorageKey(key: "isRunning")
}

@MainActor
@Observable
final class ProfileSession {
	let appStorage = AppStorage.shared

	@ObservationIgnored
	lazy var webServer = WebServer(directory: self.url)

	let device = MTLCreateSystemDefaultDevice()!

	let syphonService = SyphonService()
	let audioSourceService = AudioSourceService()

	var image: CIImage?

	var url = URL.temporaryDirectory
		.appendingPathComponent(Bundle.main.bundleIdentifier!)
		.appendingPathComponent("Livestream")

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

	var isRunning = false

	func start() async {
		print("url", url.path())

		await webServer.start()

		guard await AVCaptureDevice.requestAccess(for: .audio) else { return }

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

		let client = syphonServer.map {
			SyphonCoreImageClient($0, device: device)
		}

		let qualityLevels = HLSVideoService.QualityLevel.allCases //.prefix(1)

		let variantPlaylist =
			"""
			#EXTM3U
			#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="en",NAME="English",AUTOSELECT=YES, DEFAULT=YES,URI="audio/live.m3u8"
			
			
			""" +
			qualityLevels.map {
				"""
				#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=\($0.bitrate),RESOLUTION=\(Int($0.resolutions.width))x\(Int($0.resolutions.height)),CODECS="avc1.4d401e",AUDIO="audio"
				\($0.prefix)/live.m3u8
				"""
			}.joined(separator: "\n")
		
		print(variantPlaylist)

		await withTaskGroup(of: Void.self) { [logger, url] group in
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
						let audioService = HLSAudioService(url: url, audioDevice: audioDevice, uploader: uploader)
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
