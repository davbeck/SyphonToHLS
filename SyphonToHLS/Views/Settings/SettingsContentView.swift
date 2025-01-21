import Dependencies
import Sharing
import SwiftUI

struct SettingsContentView: View {
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
