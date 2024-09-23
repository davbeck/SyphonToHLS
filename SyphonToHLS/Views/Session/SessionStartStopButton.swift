import SwiftUI

struct SessionStartStopButton: View {
	@State private var appStorage = AppStorage.shared

	var body: some View {
		Button {
			appStorage[.isRunning].toggle()
		} label: {
			if appStorage[.isRunning] {
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
