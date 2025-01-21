import Dependencies
import Sharing
import SwiftUI

struct AWSSettingsTab: View {
	@Shared(.awsConfig) private var awsConfig

	var body: some View {
		Form {
			Section("AWS Credentials") {
				TextField("Region", text: Binding($awsConfig).region)
				TextField("S3 Bucket", text: Binding($awsConfig).bucket)
				TextField("Client Key", text: Binding($awsConfig).clientKey)
				TextField("Client Secret", text: Binding($awsConfig).clientSecret)
			}
		}
		.padding()
	}
}
