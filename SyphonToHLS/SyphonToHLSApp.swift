import Dependencies
import IssueReporting
import SwiftUI

@main
struct SyphonToHLSApp: App {
	private let session = ProfileSession.liveValue

	init() {
		if !isTesting {
			Task { [session] in
				await session.setup()
			}
		}
	}

	var body: some Scene {
		Window("Preview", id: "preview") {
			if !isTesting {
				ContentView()
			}
		}

		MenuBarExtra {
			if !isTesting {
				ContentMenuView()
			}
		} label: {
			if !isTesting {
				MenuBarLabel()
			}
		}

		Settings {
			SettingsContentView()
		}
	}
}

struct Polyfill<Source> {
	var source: Source
}

extension Polyfill: View where Source: View {
	var body: some View {
		source
	}
}

extension Polyfill: Scene where Source: Scene {
	var body: some Scene {
		source
	}
}
