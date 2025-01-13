import Dependencies
import Foundation
import OSLog
import Queue
import SotoCore
import SotoS3
import UniformTypeIdentifiers

actor HLSFileWriter: HLSWriter {
	private let queue = DispatchQueue(label: "HLSFileWriter")
	private let logger = os.Logger(category: "HLSFileWriter")

	var records: [HLSRecord] = []

	let baseURL: URL

	init(baseURL: URL) {
		self.baseURL = baseURL

		queue.async {
			try? FileManager.default.createDirectory(
				at: baseURL,
				withIntermediateDirectories: true
			)
		}
	}

	func write(_ segment: HLSSegment) async throws {
		let record = HLSRecord(
			index: segment.index,
			duration: segment.duration
		)
		records.append(record)

		queue.async { [baseURL, logger, records] in
			do {
				switch segment.type {
				case .initialization:
					try segment.data.write(
						to: baseURL
							.appending(component: "0.mp4"),
						options: .atomic
					)
				case .separable:
					try segment.data.write(
						to: baseURL
							.appending(component: record.name),
						options: .atomic
					)
					try Data(records.suffix(60 * 5).hlsPlaylist(prefix: nil).utf8).write(
						to: baseURL
							.appending(component: "live.m3u8"),
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

actor HLSS3Writer: HLSWriter {
	@Dependency(\.performanceTracker) private var performanceTracker

	let uploader: S3Uploader
	private let logger = os.Logger(category: "HLSS3Writer")

	private let liveQueue = AsyncQueue()

	var records: [HLSRecord] = []
	var writeTask: Task<Void, Never> = Task {}

	let stream: Stream

	init(uploader: S3Uploader, stream: Stream) {
		self.uploader = uploader
		self.stream = stream
	}

	func write(_ segment: HLSSegment) async throws {
		switch segment.type {
		case .initialization:
			while !Task.isCancelled {
				do {
					try await uploader.write(
						data: segment.data,
						key: "\(stream.header)/0.mp4",
						type: .mpeg4Movie,
						shouldEnableCaching: true
					)
					break
				} catch {
					logger.error("failed to write initialization segment, retrying until cancelled: \(error)")
				}
			}
		case .separable:
			let start = Date.now

			let record = HLSRecord(
				index: segment.index,
				duration: segment.duration
			)
			if let lastRecord = records.last, record.index != lastRecord.index + 1 {
				logger.warning("segment index \(record.index) is not immediately after \(lastRecord.index), resetting records")
				records.removeAll()
			}
			records.append(record)

			let segmentUpload = Task {
				func upload() async throws {
					try await uploader.write(
						data: segment.data,
						key: "\(stream.header)/\(record.name)",
						type: .segmentedVideo,
						shouldEnableCaching: false
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
			liveQueue.addOperation { [uploader, records, stream] in
				try await segmentUpload.value
				try await uploader.write(
					data: Data(records.suffix(10).hlsPlaylist(prefix: nil).utf8),
					key: "\(stream.header)/live.m3u8",
					type: .m3uPlaylist,
					shouldEnableCaching: false
				)

				let end = Date.now
				let performance = (end.timeIntervalSince(start)) / segment.duration.seconds

				await self.performanceTracker.record(performance, stream: stream, operation: .upload)
			}
		@unknown default:
			logger.error("@unknown segment type \(segment.type.rawValue)")
		}
	}
}

final class S3Uploader {
	let s3: S3
	let bucket: String

	init(s3: S3, bucket: String) {
		self.s3 = s3
		self.bucket = bucket
	}

	convenience init(_ aws: Config.AWS) {
		let client = AWSClient(
			credentialProvider: .static(
				accessKeyId: aws.clientKey,
				secretAccessKey: aws.clientSecret
			)
		)

		self.init(
			s3: S3(
				client: client,
				region: .init(
					awsRegionName: aws.region
				),
				timeout: .seconds(10)
			),
			bucket: aws.bucket
		)
	}

	deinit {
		let client = s3.client
		Task {
			try await client.shutdown()
		}
	}

	func write(
		data: Data,
		key: String,
		type: UTType,
		shouldEnableCaching: Bool
	) async throws {
		let putObjectRequest = S3.PutObjectRequest(
			body: .init(bytes: data),
			bucket: bucket,
			cacheControl: shouldEnableCaching ? "max-age=31536000, immutable" : "max-age=0, no-cache",
			contentType: type.preferredMIMEType ?? "",
			key: key
		)
		_ = try await s3.putObject(putObjectRequest)
	}
}
