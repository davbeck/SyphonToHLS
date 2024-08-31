import AVFoundation
import Metal
import Observation

extension AppStorageKey {
	static let syphonServerName = AppStorageKey(key: "syphonServerName")
	static let syphonServerApp = AppStorageKey(key: "syphonServerApp")
	static let audioDeviceID = AppStorageKey(key: "audioDeviceID")
}

@MainActor
@Observable
final class ProfileSession {
	let appStorage = AppStorage.shared

	let device = MTLCreateSystemDefaultDevice()!

	let syphonService = SyphonService()
	let audioSourceService = AudioSourceService()

	var texture: MTLTexture?

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
		guard await AVCaptureDevice.requestAccess(for: .audio) else { return }
		
		var currentTask: Task<Void, Never>?
		let currentServer = AsyncStream.makeObservationStream {
			(self.syphonServer, self.audioDevice)
		}
		for await (syphonServer, audioDevice) in currentServer {
			currentTask?.cancel()

			currentTask = Task {
				await self.start(syphonServer: syphonServer, audioDevice: audioDevice)
			}
		}
	}

	func start(syphonServer: ServerDescription?, audioDevice: AVCaptureDevice?) async {
		isRunning = true
		defer { isRunning = false }
		
		guard syphonServer != nil || audioDevice != nil else { return }
		
		let client = syphonServer.map {
			SyphonMetalClient($0, device: device)
		}

		let hlsService = HLSService(syphonClient: client, audioDevice: audioDevice)

		await withTaskGroup(of: Void.self) { group in
			group.addTask {
				await hlsService.start()
			}

			if let client {
				group.addTask { @MainActor in
					for await frame in client.frames {
						self.texture = frame
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
