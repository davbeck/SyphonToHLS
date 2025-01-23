import AVFoundation
import Dependencies
import OSLog
import Queue

protocol HLSWriter: Sendable {
	func write(_ segment: HLSSegment) async throws
}

final class WriterDelegate: NSObject, AVAssetWriterDelegate, Sendable {
	private let _idGenerator = Dependency(HLSSegmentIDGenerator.self)
	private let _clock = Dependency(\.hostTimeClock)

	let performanceTracker: PerformanceTracker

	private let logger = Logger(category: "HLSWriterDelegate")

	let queue = AsyncQueue()
	let outputs: [(writer: HLSWriter, queue: AsyncQueue)]

	let stream: Stream

	init(writers: [HLSWriter], stream: Stream) {
		self.performanceTracker = Dependency(\.performanceTracker).wrappedValue

		self.outputs = writers.map { ($0, .init()) }

		self.stream = stream

		super.init()
	}

	func assetWriter(
		_ writer: AVAssetWriter,
		didOutputSegmentData segmentData: Data,
		segmentType: AVAssetSegmentType,
		segmentReport: AVAssetSegmentReport?
	) {
		let time = _clock.wrappedValue.time
		
		queue.addOperation { [self] in
			let id: Int
			switch segmentType {
			case .initialization:
				id = 0
			case .separable:
				guard
					let segmentReport,
					let start = segmentReport.start, start.isValid,
					let end = segmentReport.end, end.isValid,
					let segmentID = await _idGenerator.wrappedValue.segmentID(for: start ..< end)
				else {
					logger.error("invalid segment \(String(describing: segmentReport))")
					return
				}

				// compare end of segment to current time
				if let duration = segmentReport.duration {
					Task {
						let encodingTime = (time - end).seconds
						let performance = encodingTime / duration.seconds

						await self.performanceTracker.record(performance, stream: stream, operation: .encode)
					}
				}

				id = segmentID
			@unknown default:
				logger.warning("unknown segment type: \(segmentType.rawValue, privacy: .public)")
				return
			}

			for (writer, queue) in self.outputs {
				queue.addOperation {
					try await writer.write(.init(
						id: id,
						data: segmentData,
						type: segmentType,
						report: segmentReport
					))
				}
			}
		}
	}
}
