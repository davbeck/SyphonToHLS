import SwiftUI
import AVFoundation
import Syphon

struct ContentView: View {
	@State private var session = ProfileSession()
	@State private var appStorage = AppStorage.shared

	var body: some View {
		VStack {
			Picker("Server", selection: $session.syphonServerID) {
				Text("None")
					.tag(ServerDescription.ID?.none)

				if let syphonServerID = session.syphonServerID, !session.syphonService.servers.contains(where: { $0.id == syphonServerID }) {
					Text("\(appStorage[.syphonServerApp]) - \(appStorage[.syphonServerName]) (Unavailable)")
						.tag(Optional.some(syphonServerID))
						.disabled(true)
				}

				ForEach(session.syphonService.servers) { server in
					Text("\(server.id.appName) - \(server.id.name)")
						.tag(Optional.some(server.id))
				}
			}
			
			Picker("Audio Source", selection: $session.audioDevice) {
				Text("None")
					.tag(AVCaptureDevice?.none)

				if let device = session.audioDevice, !session.audioSourceService.devices.contains(where: { $0.uniqueID == device.uniqueID }) {
					Text("\(device.localizedName) (Disconnected)")
						.tag(Optional.some(device))
				}

				ForEach(session.audioSourceService.devices, id: \.uniqueID) { device in
					Text(device.localizedName)
						.tag(Optional.some(device))
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
