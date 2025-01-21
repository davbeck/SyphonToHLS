import AWSSigner
import Dependencies
import Foundation
import OSLog
import Queue
import UniformTypeIdentifiers

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
						shouldEnableCaching: false,
						timeoutInterval: segment.duration.seconds
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
					shouldEnableCaching: false,
					timeoutInterval: 1
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

final class S3Uploader: Sendable {
	private let _urlSession = Dependency(\.urlSession)

	let config: AWSConfig

	init(_ config: AWSConfig) {
		self.config = config
	}

	enum Error: Swift.Error {
		case invalidURLError(urlString: String)
		case invalidURLResponse(URLResponse)
		case unexpectedStatusCode(Int, responseBody: String)
	}

	func write(
		data: Data,
		key: String,
		type: UTType,
		shouldEnableCaching: Bool,
		timeoutInterval: TimeInterval = 60
	) async throws {
		let urlString = "https://\(config.bucket).s3.\(config.region).amazonaws.com/\(key)"
		guard let url = URL(string: urlString) else {
			throw Error.invalidURLError(urlString: urlString)
		}

		let credentials = StaticCredential(
			accessKeyId: config.clientKey,
			secretAccessKey: config.clientSecret
		)
		let signer = AWSSigner(
			credentials: credentials,
			name: "s3",
			region: config.region
		)
		let signedHeaders = signer.signHeaders(
			url: url,
			method: .PUT,
			headers: [
				"Cache-Control": shouldEnableCaching ? "max-age=31536000, immutable" : "max-age=0, no-cache",
				"Content-Type": type.preferredMIMEType ?? "",
			],
			body: .data(data)
		)

		var urlRequest = URLRequest(url: url)
		urlRequest.httpMethod = "PUT"
		for (name, value) in signedHeaders {
			urlRequest.addValue(value, forHTTPHeaderField: name)
		}
		urlRequest.timeoutInterval = timeoutInterval

		let (outputData, response) = try await _urlSession.wrappedValue.upload(for: urlRequest, from: data)

		guard let response = response as? HTTPURLResponse else { throw Error.invalidURLResponse(response) }
		guard response.statusCode == 200 else {
			throw Error.unexpectedStatusCode(
				response.statusCode,
				responseBody: String(bytes: outputData, encoding: .utf8) ?? ""
			)
		}
	}
}
