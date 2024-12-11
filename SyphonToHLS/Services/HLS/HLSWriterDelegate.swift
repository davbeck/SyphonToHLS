import AVFoundation
import OSLog
import Queue

protocol HLSWriter: Sendable {
	func write(_ segment: HLSSegment) async throws
}

final class WriterDelegate: NSObject, AVAssetWriterDelegate, Sendable {
	private let logger = Logger(category: "HLSWriterDelegate")

	let outputs: [(writer: HLSWriter, queue: AsyncQueue)]
	let start: CMTime
	let segmentInterval: CMTime

	init(start: CMTime, segmentInterval: CMTime, writers: [HLSWriter]) {
		self.start = start
		self.segmentInterval = segmentInterval
		self.outputs = writers.map { ($0, .init()) }

		super.init()
	}

	func assetWriter(
		_ writer: AVAssetWriter,
		didOutputSegmentData segmentData: Data,
		segmentType: AVAssetSegmentType,
		segmentReport: AVAssetSegmentReport?
	) {
		let index: Int
		switch segmentType {
		case .initialization:
			index = 0
		case .separable:
			guard let segmentReport, let start = segmentReport.start, start.isValid else {
				logger.error("invalid segment \(String(describing: segmentReport))")
				return
			}
			index = Int((start.seconds / segmentInterval.seconds).rounded())
		@unknown default:
			logger.warning("unknown segment type: \(segmentType.rawValue, privacy: .public)")
			return
		}

		for (writer, queue) in self.outputs {
			queue.addOperation {
				try await writer.write(.init(
					index: index,
					data: segmentData,
					type: segmentType,
					report: segmentReport
				))
			}
		}
	}
}
