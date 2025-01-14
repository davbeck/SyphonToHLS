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
			
			SessionMonitorSourcePicker()

			if let syphonClient = session.syphonClient {
				SyphonPreviewView(client: syphonClient)
			}

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
