import SwiftUI
import Syphon

struct ContentView: View {
	let syphonService = SyphonService()

	@State private var device = MTLCreateSystemDefaultDevice()!
	@State private var client: SyphonMetalClient?
	@State private var hlsService: HLSService?

	@State private var texture: MTLTexture?

	var body: some View {
		VStack {
			MetalView(device: device, texture: texture)
		}
		.padding()
		.task {
			let servers = syphonService.servers
			print("servers", servers)
			guard let server = servers.first else {
				return
			}

			let hlsService = HLSService()
			self.hlsService = hlsService
			await hlsService.start()

			let client = SyphonMetalClient(
				server,
				device: device
			)

			for await frame in client.frames {
				self.texture = frame

				await hlsService.writeFrame(forTexture: frame)
			}

			self.client = client

			print("client", client)
		}
	}
}

#Preview {
	ContentView()
}
