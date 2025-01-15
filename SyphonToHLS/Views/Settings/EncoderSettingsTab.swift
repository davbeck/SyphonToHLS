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
			
			LabeledContent("Quality levels") {
				VStack(alignment: .leading) {
					ForEach(VideoQualityLevel.allCases, id: \.self) { level in
						Toggle(level.name, isOn: $configManager.config.encoder.qualityLevels[contains: level])
					}
				}
			}
		}
		.padding()
	}
}

#Preview {
	EncoderSettingsTab()
}
