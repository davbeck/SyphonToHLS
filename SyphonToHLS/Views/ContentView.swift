import AVFoundation
import Dependencies
import SwiftUI
import Syphon

struct ContentView: View {
	@Dependency(\.configManager) private var configManager

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
