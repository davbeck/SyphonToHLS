import Foundation
import OSLog
import Queue
import SotoCore
import SotoS3
import UniformTypeIdentifiers

// struct HLSWriterChunk: Sendable {
//	var data: Data
//	var key: String
//	var type: UTType
//	var shouldEnableCaching: Bool
// }

protocol HLSWriter: Sendable {
	func write(_ segment: HLSSegment) async throws
}

actor HLSFileWriter: HLSWriter {
	private let queue = DispatchQueue(label: "HLSFileWriter")
	private let logger = os.Logger(category: "HLSFileWriter")

	var records: [HLSRecord] = []

	let baseURL: URL
	let prefix: String

	init(baseURL: URL, prefix: String) {
		self.baseURL = baseURL
		self.prefix = prefix

		queue.async {
			try? FileManager.default.createDirectory(
				at: baseURL.appending(component: prefix),
				withIntermediateDirectories: true
			)
		}
	}

	func write(_ segment: HLSSegment) async throws {
		let record = HLSRecord(
			index: (records.map(\.index).max() ?? 0) + 1,
			duration: segment.duration
		)
		records.append(record)

		queue.async { [baseURL, prefix, logger, records] in
			do {
				switch segment.type {
				case .initialization:
					try segment.data.write(
						to: baseURL
							.appending(component: prefix)
							.appending(component: "0.mp4"),
						options: .atomic
					)
				case .separable:
					try segment.data.write(
						to: baseURL
							.appending(component: prefix)
							.appending(component: record.name),
						options: .atomic
					)
					try Data(records.suffix(60 * 5).hlsPlaylist(prefix: prefix).utf8).write(
						to: baseURL
							.appending(component: "live.m3u8"),
						options: .atomic
					)
					try Data(records.hlsPlaylist(prefix: nil).utf8).write(
						to: baseURL
							.appending(component: prefix)
							.appending(component: "play.m3u8"),
						options: .atomic
					)
				@unknown default:
					return
				}
			} catch {
				logger.error("failed to write segment: \(error)")
			}
		}
	}
}

struct AppStorageCredentialProvider: CredentialProvider {
	@MainActor
	func getCredential(logger: Logging.Logger) async throws -> any SotoSignerV4.Credential {
		let appStorage = AppStorage.shared
		return StaticCredential(
			accessKeyId: appStorage[.awsClientKey],
			secretAccessKey: appStorage[.awsClientSecret]
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

actor HLSS3Writer: HLSWriter {
	let client = AWSClient.app
	private let logger = os.Logger(category: "HLSS3Writer")

	private let liveQueue = AsyncQueue()
	private let playQueue = AsyncQueue()

	let prefix: String

	var records: [HLSRecord] = []
	var writeTask: Task<Void, Never> = Task {}

	init(prefix: String) {
		self.prefix = prefix
	}

	func write(_ segment: HLSSegment) async throws {
		switch segment.type {
		case .initialization:
			while !Task.isCancelled {
				do {
					try await self.write(
						data: segment.data,
						key: "\(prefix)/0.mp4",
						type: .mpeg4Movie,
						shouldEnableCaching: true
					)
					break
				} catch {
					logger.error("failed to write initialization segment, retrying until cancelled: \(error)")
				}
			}
		case .separable:
			let record = HLSRecord(
				index: Int(round(segment.start.seconds / segment.duration.seconds)),
				duration: segment.duration
			)
			records.append(record)

			let segment = Task {
				func upload() async throws {
					try await self.write(
						data: segment.data,
						key: prefix + "/" + record.name,
						type: .segmentedVideo,
						shouldEnableCaching: true
					)
				}

				do {
					try await upload()
				} catch {
					logger.error("failed to upload segment, retrying: \(error)")

					do {
						try await upload()
					} catch {
						logger.error("failed to upload segment: \(error)")

						self.records.removeAll(where: { $0.index <= record.index })

						throw error
					}
				}
			}
			liveQueue.addOperation { [weak self, records, prefix] in
				try await segment.value
				try await self?.write(
					data: Data(records.suffix(10).hlsPlaylist(prefix: prefix).utf8),
					key: "live.m3u8",
					type: .m3uPlaylist,
					shouldEnableCaching: false
				)
			}
			playQueue.addOperation { [weak self, records, prefix] in
				try await segment.value
				try await self?.write(
					data: Data(records.hlsPlaylist(prefix: nil).utf8),
					key: prefix + "/play.m3u8",
					type: .m3uPlaylist,
					shouldEnableCaching: false
				)
			}
		@unknown default:
			logger.error("@unknown segment type \(segment.type.rawValue)")
		}
	}

	private func write(
		data: Data,
		key: String,
		type: UTType,
		shouldEnableCaching: Bool
	) async throws {
		let (s3, bucket) = await s3()

		let putObjectRequest = S3.PutObjectRequest(
			body: .init(bytes: data),
			bucket: bucket,
			cacheControl: shouldEnableCaching ? "max-age=31536000, immutable" : "max-age=0, no-cache",
			contentType: type.preferredMIMEType ?? "",
			key: key
		)
		_ = try await s3.putObject(putObjectRequest)
	}

	@MainActor
	private func s3() -> (S3, bucket: String) {
		let appStorage = AppStorage.shared

		let bucket: String = appStorage[.awsS3Bucket]
		let s3 = S3(client: client, region: .init(awsRegionName: appStorage[.awsRegion]), timeout: .seconds(5))

		return (s3, bucket)
	}
}
