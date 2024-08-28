import SwiftUI

struct SettingsContentView: View {
	@AppStorage("AWSRegion") private var awsRegion: String = ""
	@AppStorage("AWSS3Bucket") private var awsS3Bucket: String = ""
	@AppStorage("AWSClientKey") private var awsClientKey: String = ""
	@AppStorage("AWSClientSecret") private var awsClientSecret: String = ""

	var body: some View {
		Form {
			Section("AWS Credentials") {
				TextField("Region", text: $awsRegion)
				TextField("S3 Bucket", text: $awsS3Bucket)
				TextField("Client Key", text: $awsClientKey)
				TextField("Client Secret", text: $awsClientSecret)
			}
		}
		.padding()
		.frame(width: 500)
	}
}

#Preview {
	SettingsContentView()
}
