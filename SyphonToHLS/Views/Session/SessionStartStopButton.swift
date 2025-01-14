import Dependencies
import SwiftUI

struct SessionStartStopButton: View {
	private let session = ProfileSession.liveValue

	var body: some View {
		Button {
			session.isRunning.toggle()
		} label: {
			if session.isRunning {
				Text("Stop")
			} else {
				Text("Start")
			}
		}
	}
}

#Preview {
	SessionStartStopButton()
}
