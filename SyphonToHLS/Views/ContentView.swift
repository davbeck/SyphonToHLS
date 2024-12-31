import AVFoundation
import SwiftUI
import Syphon
import Dependencies

struct ContentView: View {
	@Dependency(\.profileSession) private var session
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
	}
}

#Preview {
	ContentView()
}
