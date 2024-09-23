import AVFoundation
import SwiftUI
import Syphon

struct ContentView: View {
	@State private var session = ProfileSession.shared
	@State private var appStorage = AppStorage.shared

	var body: some View {
		VStack {
			SessionVideoSourcePicker()

			SessionAudioSourcePicker()

			MetalView(
				device: session.device,
				image: session.image
			)

			HStack {
				Spacer()

				SessionStartStopButton()
			}
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
