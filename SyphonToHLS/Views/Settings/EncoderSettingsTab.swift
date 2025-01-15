import Dependencies
import SwiftUI

struct EncoderSettingsTab: View {
	@Dependency(\.configManager) private var configManager

	var body: some View {
		@Bindable var configManager = self.configManager

		Form {
			HStack {
				Slider(
					value: $configManager.config.encoder.preferredOutputSegmentInterval,
					in: 1 ... 30,
					step: 1
				) {
					Text("Segment length")
				}
				
				Text(Duration.seconds(configManager.config.encoder.preferredOutputSegmentInterval).formatted(.units(allowed: [.seconds], zeroValueUnits: .show(length: 2))))
					.font(.callout)
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		}
		.padding()
	}
}

#Preview {
	EncoderSettingsTab()
}
