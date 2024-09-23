import SwiftUI

struct MenuBarLabel: View {
	@State private var appStorage = AppStorage.shared
	@State private var animationValue: Double = 0
	
	var body: some View {
		Image(systemName: "antenna.radiowaves.left.and.right", variableValue: animationValue)
			.animation(.default, value: animationValue)
			.task(id: appStorage[.isRunning]) {
				if appStorage[.isRunning] {
					while !Task.isCancelled {
						try? await Task.sleep(for: .seconds(0.5))
						animationValue += 0.5
						if animationValue > 1 {
							animationValue = 0
						}
					}
				} else {
					animationValue = 0
				}
			}
	}
}

@main
struct SyphonToHLSApp: App {
	@Environment(\.openWindow) private var openWindow
	
	init() {
		Task {
			await ProfileSession.shared.start()
		}
	}

	var body: some Scene {
		MenuBarExtra {
			ContentMenuView()
		} label: {
			MenuBarLabel()
		}

		// defaultLaunchBehavior is macOS 15 only
		// ideally we could provide this as an option in the menu bar
//		Window("Preview", id: "preview") {
//			ContentView()
//		}
//		.defaultLaunchBehavior(.suppressed)

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
