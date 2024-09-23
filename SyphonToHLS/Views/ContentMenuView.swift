import AVFoundation
import SwiftUI

struct ContentMenuView: View {
	@State private var session = ProfileSession.shared
	@State private var appStorage = AppStorage.shared

	var body: some View {
		Section {
			SessionVideoSourcePicker()

			SessionAudioSourcePicker()
			
			SessionStartStopButton()
		}

		Section {
			SettingsLink()
			
			Button("Quit") {
				NSApplication.shared.terminate(nil)
			}
		}
	}
}
