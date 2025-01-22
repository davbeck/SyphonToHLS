import CoreMedia
import Dependencies
import Sharing

/// Keeps track of segment numbers, aligning segments with existing IDs.
actor HLSSegmentIDGenerator {
	private let _defaultStore = Dependency(\.defaultAppStorage)

	private var lastSegmentID: Int
	private var segments: [Range<CMTime>] = []

	init() {
		lastSegmentID = _defaultStore.wrappedValue.integer(forKey: "lastSegmentID")
	}

	private func nextSegmentID() -> Int {
		lastSegmentID += 1

		_defaultStore.wrappedValue.set(lastSegmentID, forKey: "lastSegmentID")

		return lastSegmentID
	}

	func segmentID(for range: Range<CMTime>) -> Int? {
		// reduce precision to more loosely match segments
		// for instance a segment that is just barely overlapping with another
		let range = CMTimeConvertScale(
			range.lowerBound,
			timescale: 15,
			method: .default
		) ..< CMTimeConvertScale(
			range.upperBound,
			timescale: 15,
			method: .default
		)

		if let last = segments.last {
			if range.lowerBound >= last.upperBound {
				segments.append(range)

				return nextSegmentID()
			} else if let index = segments.lastIndex(where: { $0.overlaps(range) }) {
				let offset = index.distance(to: segments.endIndex) - 1
				return lastSegmentID - offset
			} else {
				return nil
			}
		} else {
			segments.append(range)

			return nextSegmentID()
		}
	}
}

extension HLSSegmentIDGenerator: DependencyKey {
	static let liveValue = HLSSegmentIDGenerator()
}
