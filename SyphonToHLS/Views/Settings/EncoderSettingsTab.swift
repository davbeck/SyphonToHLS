import Dependencies
import Sharing
import SwiftUI

struct EncoderSettingsTab: View {
	@Shared(.encoderConfig) private var encoderConfig

	var body: some View {
		Form {
			HStack {
				Slider(
					value: Binding($encoderConfig).preferredOutputSegmentInterval,
					in: 1 ... 30,
					step: 1
				) {
					Text("Segment length")
				}

				Text(Duration.seconds(encoderConfig.preferredOutputSegmentInterval).formatted(.units(allowed: [.seconds], zeroValueUnits: .show(length: 2))))
					.font(.callout)
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}

			LabeledContent("Quality levels") {
				VStack(alignment: .leading) {
					ForEach(VideoQualityLevel.allCases, id: \.self) { level in
						Toggle(level.name, isOn: Binding($encoderConfig).qualityLevels[contains: level])
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
