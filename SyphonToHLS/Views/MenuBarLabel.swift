import Dependencies
import IssueReporting
import SwiftUI

struct MenuBarLabel: View {
	private let session = ProfileSession.liveValue

	@State private var animationValue: Double = 0

	var body: some View {
		Image(systemName: "antenna.radiowaves.left.and.right", variableValue: animationValue)
			.animation(.default, value: animationValue)
			.task(id: session.isRunning) {
				if session.isRunning {
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
