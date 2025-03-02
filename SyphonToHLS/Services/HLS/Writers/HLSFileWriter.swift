import Foundation
import OSLog

actor HLSFileWriter: HLSWriter {
	private let logger = os.Logger(category: "HLSFileWriter")

	var records: [HLSRecord] = []

	let baseURL: URL

	init(baseURL: URL) {
		self.baseURL = baseURL

		try? FileManager.default.createDirectory(
			at: baseURL,
			withIntermediateDirectories: true
		)
	}

	func write(_ segment: HLSSegment) async throws {
		do {
			switch segment.type {
			case .initialization:
				try segment.data.write(
					to: baseURL
						.appending(component: "0.mp4"),
					options: .atomic
				)
			case .separable:
				let record = HLSRecord(
					index: segment.id,
					discontinuityIndex: 0,
					duration: segment.duration
				)
				records.append(record)

				try segment.data.write(
					to: baseURL
						.appending(component: record.name),
					options: .atomic
				)
				try Data(records.suffix(10).hlsPlaylist(prefix: nil).utf8).write(
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
