import Foundation
import SotoCore
import SotoS3
import UniformTypeIdentifiers

struct HLSWriterChunk: Sendable {
	var data: Data
	var key: String
	var type: UTType
}

protocol HLSWriter {
	func write(_ chunk: HLSWriterChunk) async throws
}

struct HLSFileWriter: HLSWriter {
	let baseURL: URL

	func write(_ chunk: HLSWriterChunk) async throws {
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global().async {
				continuation.resume(with: Result {
					try chunk.data.write(
						to: baseURL.appendingPathComponent(chunk.key),
						options: .atomic
					)
				})
			}
		}
	}
}

struct AppStorageCredentialProvider: CredentialProvider {
	@MainActor
	func getCredential(logger: Logging.Logger) async throws -> any SotoSignerV4.Credential {
		let appStorage = AppStorage.shared
		return StaticCredential(
			accessKeyId: appStorage.awsClientKey,
			secretAccessKey: appStorage.awsClientSecret
		)
	}
}

public extension CredentialProviderFactory {
	static var app: CredentialProviderFactory {
		.custom { context in
			AppStorageCredentialProvider()
		}
	}
}

extension AWSClient {
	static let app = AWSClient(credentialProvider: .app)
}

struct HLSS3Writer: HLSWriter {
	let client = AWSClient.app

	@MainActor
	func write(_ chunk: HLSWriterChunk) async throws {
		let appStorage = AppStorage.shared
		
		let bucket: String = appStorage.awsS3Bucket
		
		let s3 = S3(client: client, region: .init(awsRegionName: appStorage.awsRegion))

		let putObjectRequest = S3.PutObjectRequest(
			body: .init(bytes: chunk.data),
			bucket: bucket,
//			cacheControl: "",
			contentType: chunk.type.preferredMIMEType ?? "",
			key: chunk.key
		)
		_ = try await s3.putObject(putObjectRequest)
	}
}
