import AVFoundation
import SwiftUI
import Syphon

struct ContentView: View {
	private let session = ProfileSession.liveValue

	var body: some View {
		VStack {
			SessionVideoSourcePicker()

			SessionAudioSourcePicker()

			SessionMonitorSourcePicker()

			if let frameSource = session.frameSource {
				FrameSourcePreviewView(frameSource: frameSource)
			} else {
				Rectangle().fill(Color.black)
			}

			PerformanceView()

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
