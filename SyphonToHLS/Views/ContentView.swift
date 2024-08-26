import SwiftUI
import Syphon

struct ContentView: View {
	@State private var session = ProfileSession()
	
	var body: some View {
		VStack {
			Picker("Server", selection: $session.syphonServerID) {
				ForEach(session.syphonService.servers) { server in
					Text("\(server.appName) - \(server.name)")
						.tag(Optional.some(server.id))
				}
			}
			
			MetalView(
				device: session.device,
				texture: session.texture
			)
		}
		.padding()
		.task {
			await session.start()
		}
	}
}

#Preview {
	ContentView()
}
