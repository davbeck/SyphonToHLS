import Dependencies
import IssueReporting
import SwiftUI

@main
struct SyphonToHLSApp: App {
	@Dependency(\.profileSession) private var session

	init() {
		if !isTesting {
			Task { [session] in
				await session.setup()
			}
		}
	}

	var body: some Scene {
		MenuBarExtra {
			if !isTesting {
				ContentMenuView()
			}
		} label: {
			if !isTesting {
				MenuBarLabel()
			}
		}
		.menuBarExtraStyle(.window)

		Window("Preview", id: "preview") {
			if !isTesting {
				ContentView()
			}
		}
		.defaultLaunchBehavior(.suppressed)

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
