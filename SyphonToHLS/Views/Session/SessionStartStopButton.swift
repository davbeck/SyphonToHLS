import SwiftUI
import Dependencies

struct SessionStartStopButton: View {
	@Dependency(\.profileSession) private var profileSession

	var body: some View {
		Button {
			profileSession.isRunning.toggle()
		} label: {
			if profileSession.isRunning {
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
