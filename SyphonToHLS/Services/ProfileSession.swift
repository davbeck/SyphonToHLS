import AVFoundation
import Metal
import Observation

@MainActor
@Observable
final class ProfileSession {
	let device = MTLCreateSystemDefaultDevice()!

	let syphonService = SyphonService()

	var texture: MTLTexture?

	var syphonServerID: ServerDescription.ID?

	var syphonServer: ServerDescription? {
		guard let syphonServerID else { return nil }
		return syphonService.servers.first(where: { $0.id == syphonServerID })
	}

	var isRunning = false

	func start() async {
		if syphonServerID == nil {
			syphonServerID = syphonService.servers.first?.id
		}

		var currentTask: Task<Void, Never>?
		let currentServer = AsyncStream.makeObservationStream {
			self.syphonServer
		}
		for await server in currentServer {
			currentTask?.cancel()
			guard let server else { continue }

			currentTask = Task {
				await self.start(server)
			}
		}
	}

	func start(_ server: ServerDescription) async {
		isRunning = true
		defer { isRunning = false }

		guard await AVCaptureDevice.requestAccess(for: .audio) else { return }

		let hlsService = HLSService()

		let client = SyphonMetalClient(
			server,
			device: device
		)

		await withTaskGroup(of: Void.self) { group in
			group.addTask {
				await hlsService.start()
			}
			
			group.addTask { @MainActor in
				do {
					for await frame in client.frames {
						self.texture = frame

						try await hlsService.writeFrame(forTexture: frame)
					}
				} catch {
					print(error)
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
