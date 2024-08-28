import SwiftUI

@main
struct SyphonToHLSApp: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
		}

		Settings {
			SettingsContentView()
		}
	}
}
