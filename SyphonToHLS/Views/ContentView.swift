import AVFoundation
import SwiftUI
import Syphon
import Dependencies

struct ContentView: View {
	private let session = ProfileSession.liveValue

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
