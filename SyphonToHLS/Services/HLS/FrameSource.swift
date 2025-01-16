import CoreImage
import CoreMedia
import Dependencies

struct Frame: @unchecked Sendable {
	var time: CMTime
	var image: CIImage
}

protocol FrameSource: AnyObject, Sendable {
	var frames: any AsyncSequence<Frame, Never> { get }
}

final class NDIFrameSource: FrameSource, Sendable {
	private let _date = Dependency(\.date)
	private let clock = CMClock.hostTimeClock
	let player: NDIPlayer

	init(player: NDIPlayer) {
		self.player = player
	}

	var frames: any AsyncSequence<Frame, Never> {
		player.videoFrames.compactMap { [_date, clock] frame -> Frame? in
			guard let pixelBuffer = frame.pixelBuffer else { return nil }
			let image = CIImage(cvPixelBuffer: pixelBuffer)

			// convert world clock timestamp to host media clock by subtracting the diff from our current time
			let date = _date.wrappedValue.now
			let time = clock.time

			let diff: TimeInterval
			if let timestamp = frame.timestamp {
				diff = date.timeIntervalSince(timestamp)
			} else {
				diff = 0
			}

			return Frame(
				time: time - CMTime(seconds: diff, preferredTimescale: 10_000_000),
				image: image
			)
		}
	}
}
