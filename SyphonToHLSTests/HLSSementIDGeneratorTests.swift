import CoreMedia
import Testing
import Dependencies
@testable import SyphonToHLS

struct HLSSementIDGeneratorTests {
	// MARK: - Tests
	
	@Test func segmentID_startsAt1() async throws {
		let sut = HLSSegmentIDGenerator()

		let segmentID = await sut.segmentID(
			for: CMTime(seconds: 0, preferredTimescale: 30) ..< CMTime(seconds: 6, preferredTimescale: 30)
		)

		#expect(segmentID == 1)
	}
	
	@Test func segmentID_movesSegmentForward() async throws {
		let sut = HLSSegmentIDGenerator()
		for i in 0..<3 {
			_ = await sut.segmentID(
				for: CMTime(seconds: Double(i * 6), preferredTimescale: 30) ..< CMTime(seconds: Double(i * 6) + 6, preferredTimescale: 30)
			)
		}

		let segmentID = await sut.segmentID(
			for: CMTime(seconds: 18, preferredTimescale: 30) ..< CMTime(seconds: 24, preferredTimescale: 30)
		)

		#expect(segmentID == 4)
	}
	
	@Test func segmentID_movesSegmentForwardWithRounding() async throws {
		let sut = HLSSegmentIDGenerator()
		for i in 0..<3 {
			_ = await sut.segmentID(
				for: CMTime(seconds: Double(i * 6), preferredTimescale: 30) ..< CMTime(seconds: Double(i * 6) + 6, preferredTimescale: 30)
			)
		}

		let segmentID = await sut.segmentID(
			for: CMTime(value: 18 * 90 - 1, timescale: 90) ..< CMTime(seconds: 24, preferredTimescale: 30)
		)

		#expect(segmentID == 4)
	}
	
	@Test func segmentID_matchesExistingSegments() async throws {
		let sut = HLSSegmentIDGenerator()
		for i in 0..<3 {
			_ = await sut.segmentID(
				for: CMTime(seconds: Double(i * 6), preferredTimescale: 30) ..< CMTime(seconds: Double(i * 6) + 6, preferredTimescale: 30)
			)
		}

		let segmentID = await sut.segmentID(
			for: CMTime(seconds: 12, preferredTimescale: 30) ..< CMTime(seconds: 18, preferredTimescale: 30)
		)

		#expect(segmentID == 3)
	}
	
	@Test func segmentID_matchesExistingSegmentsThatOverlap() async throws {
		let sut = HLSSegmentIDGenerator()
		for i in 0..<3 {
			_ = await sut.segmentID(
				for: CMTime(seconds: Double(i * 6), preferredTimescale: 30) ..< CMTime(seconds: Double(i * 6) + 6, preferredTimescale: 30)
			)
		}

		let segmentID = await sut.segmentID(
			for: CMTime(seconds: 16, preferredTimescale: 30) ..< CMTime(seconds: 22, preferredTimescale: 30)
		)

		#expect(segmentID == 3)
	}
	
	@Test func segmentID_doesNotMatchOldSegments() async throws {
		let sut = HLSSegmentIDGenerator()
		for i in 3..<6 {
			_ = await sut.segmentID(
				for: CMTime(seconds: Double(i * 6), preferredTimescale: 30) ..< CMTime(seconds: Double(i * 6) + 6, preferredTimescale: 30)
			)
		}

		let segmentID = await sut.segmentID(
			for: CMTime(seconds: 12, preferredTimescale: 30) ..< CMTime(seconds: 18, preferredTimescale: 30)
		)

		#expect(segmentID == nil)
	}
}
