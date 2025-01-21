import Dependencies
import Foundation
import Synchronization
import Testing
@testable import SyphonToHLS

@MainActor
class PerformanceTrackerTests {
	private let now = Mutex(Date(timeIntervalSinceReferenceDate: 0))
	private let logURL = URL.temporaryDirectory.appending(component: UUID().uuidString)

	private lazy var sut = withDependencies {
		$0.date = DateGenerator {
			self.now.withLock { $0 }
		}
	} operation: {
		PerformanceTracker(logURL: logURL)
	}
	
	// MARK: - Tests

	@Test func writesLog() async throws {
		for _ in 0 ..< 100 {
			for stream in Stream.allCases {
				for operation in PerformanceTracker.Operation.allCases {
					sut.record(0.3, stream: stream, operation: operation)
					sut.record(0.1, stream: stream, operation: operation)
					sut.record(0.2, stream: stream, operation: operation)
				}
			}
		}

		let log = try String(contentsOf: logURL, encoding: .utf8)
			.split(separator: "\n")

		try #require(log.count == 2)
		#expect(log[0] == header)
		#expect(log[1] == "2001-01-01T00:00:00Z, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3")
	}

	@Test func writesLogPeriodically() async throws {
		for _ in 0 ..< 100 {
			for stream in Stream.allCases {
				for operation in PerformanceTracker.Operation.allCases {
					sut.record(0.3, stream: stream, operation: operation)
					sut.record(0.1, stream: stream, operation: operation)
					sut.record(0.2, stream: stream, operation: operation)
				}
			}
		}
		now.withLock { $0 += 60 * 6 }
		sut.record(1e10, stream: .video(.high), operation: .encode)

		let log = try String(contentsOf: logURL, encoding: .utf8)
			.split(separator: "\n")

		try #require(log.count == 3)
		#expect(log[0] == header)
		#expect(log[1] == "2001-01-01T00:00:00Z, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3")
		#expect(log[2] == "2001-01-01T00:06:00Z, 200,000,000.196, 10,000,000,000, 0.198, 0.3, 0.198, 0.3, 0.198, 0.3, 0.198, 0.3, 0.198, 0.3, 0.198, 0.3, 0.198, 0.3")
	}

	@Test func appendsToLog() async throws {
		try """
		\(header)
		2001-01-01T00:06:00Z, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1

		"""
			.write(to: logURL, atomically: true, encoding: .utf8)

		for _ in 0 ..< 100 {
			for stream in Stream.allCases {
				for operation in PerformanceTracker.Operation.allCases {
					sut.record(0.3, stream: stream, operation: operation)
					sut.record(0.1, stream: stream, operation: operation)
					sut.record(0.2, stream: stream, operation: operation)
				}
			}
		}

		let log = try String(contentsOf: logURL, encoding: .utf8)
			.split(separator: "\n")

		print(log)
		try #require(log.count == 3)
		#expect(log[0] == header)
		#expect(log[1] == "2001-01-01T00:06:00Z, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1")
		#expect(log[2] == "2001-01-01T00:00:00Z, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3, 0.2, 0.3")
	}

	// MARK: - Helpers

	private let header = "Timestamp, High encode average, High encode max, High upload average, High upload max, Medium encode average, Medium encode max, Medium upload average, Medium upload max, Low encode average, Low encode max, Low upload average, Low upload max, Audio encode average, Audio encode max, Audio upload average, Audio upload max"
}
