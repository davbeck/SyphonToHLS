import Dependencies
import SwiftUI

struct SettingsContentView: View {
	@Dependency(\.configManager) private var configManager

	var body: some View {
		TabView {
			Tab {
				EncoderSettingsTab()
			} label: {
				Text("Encoder")
			}
			
			Tab {
				AWSSettingsTab()
			} label: {
				Text("AWS")
			}
		}
		.frame(width: 500)
	}
}

#Preview {
	SettingsContentView()
}
