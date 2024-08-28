import SwiftUI

struct SettingsContentView: View {
	@State private var appStorage = AppStorage.shared

	var body: some View {
		Form {
			Section("AWS Credentials") {
				TextField("Region", text: $appStorage.awsRegion)
				TextField("S3 Bucket", text: $appStorage.awsS3Bucket)
				TextField("Client Key", text: $appStorage.awsClientKey)
				TextField("Client Secret", text: $appStorage.awsClientSecret)
			}
		}
		.padding()
		.frame(width: 500)
	}
}

#Preview {
	SettingsContentView()
}
