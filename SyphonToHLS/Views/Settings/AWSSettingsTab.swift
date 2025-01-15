import Dependencies
import SwiftUI

struct AWSSettingsTab: View {
	@Dependency(\.configManager) private var configManager

	var body: some View {
		@Bindable var configManager = self.configManager

		Form {
			Section("AWS Credentials") {
				TextField("Region", text: $configManager.config.aws.region)
				TextField("S3 Bucket", text: $configManager.config.aws.bucket)
				TextField("Client Key", text: $configManager.config.aws.clientKey)
				TextField("Client Secret", text: $configManager.config.aws.clientSecret)
			}
		}
		.padding()
	}
}
