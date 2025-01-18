import Dependencies
import Foundation
import OSLog

@MainActor
@Observable
class PerformanceTracker {
	@ObservationIgnored
	@Dependency(\.date) var date

	private let logger = Logger(category: "Performance")

	enum Operation: CaseIterable {
		case encode
		case upload

		var header: String {
			switch self {
			case .encode:
				"encode"
			case .upload:
				"upload"
			}
		}
	}

	struct Key: Hashable, CaseIterable {
		var stream: Stream
		var operation: Operation

		static var allCases: [PerformanceTracker.Key] {
			Stream.allCases.flatMap { stream in
				Operation.allCases.map { operation in
					Key(stream: stream, operation: operation)
				}
			}
		}

		var header: String {
			"\(stream.header.capitalized) \(operation.header)"
		}
	}

	private var stats: [Key: [Double]] = [:]

	let logURL: URL

	nonisolated
	init(logURL: URL = URL.moviesDirectory.appending(component: ".SyphonToHLSPerformance.csv")) {
		self.logURL = logURL
	}

	func record(_ performance: Double, stream: Stream, operation: Operation) {
		let key = Key(stream: stream, operation: operation)
		var records = stats[key] ?? []

		records.append(performance)
		while records.count > 50 {
			records.removeFirst()
		}

		stats[key] = records

		if records.count >= 50, needsWriting {
			write()
		}
	}
	
	func max(stream: Stream, operation: Operation) -> Double {
		stats[.init(stream: stream, operation: operation)]?.max() ?? 0
	}
	
	func max(stream: Stream) -> Double {
		Operation.allCases.map { max(stream: stream, operation: $0) }.reduce(0, +)
	}

	func average(stream: Stream, operation: Operation) -> Double {
		let stats = self.stats[.init(stream: stream, operation: operation)] ?? []
		return stats.reduce(0, +) / Double(stats.count)
	}
	
	func average(stream: Stream) -> Double {
		Operation.allCases.map { average(stream: stream, operation: $0) }.reduce(0, +)
	}

	// MARK: - Log

	private var lastWritten: Date?
	private var fileHandle: FileHandle?

	var needsWriting: Bool {
		if let lastWritten {
			return date.now.timeIntervalSince(lastWritten) > 60 * 5
		}

		return true
	}

	func setupFileHandle() throws -> FileHandle {
		if let fileHandle {
			return fileHandle
		}

		if !FileManager.default.fileExists(atPath: logURL.path()) {
			let header = "Timestamp, " + Key.allCases.map { key -> String in
				"\(key.header) average, \(key.header) max"
			}
			.joined(separator: ", ") + "\n"

			try header.write(to: logURL, atomically: true, encoding: .utf8)
		}

		let fileHandle = try FileHandle(forWritingTo: logURL)
		fileHandle.seekToEndOfFile()
		return fileHandle
	}

	func write() {
		lastWritten = date.now

		let row = date.now.formatted(.iso8601) + ", " + Key.allCases.map { key -> String in
			let stats = self.stats[key] ?? []
			let max = stats.max() ?? 0
			let average = stats.reduce(0, +) / Double(stats.count)

			return "\(average.formatted()), \(max.formatted())"
		}
		.joined(separator: ", ") + "\n"

		do {
			let fileHandle = try setupFileHandle()
			try fileHandle.write(contentsOf: Data(row.utf8))
		} catch {
			logger.error("failed to write performance data: \(error)")
		}
	}
}

extension PerformanceTracker: DependencyKey {
	nonisolated
	static let liveValue: PerformanceTracker = .init()
}

extension DependencyValues {
	var performanceTracker: PerformanceTracker {
		get { self[PerformanceTracker.self] }
		set { self[PerformanceTracker.self] = newValue }
	}
}
