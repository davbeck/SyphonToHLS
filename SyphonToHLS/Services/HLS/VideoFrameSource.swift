import CoreImage
import CoreMedia
import Dependencies
import NDI

struct VideoFrame: @unchecked Sendable {
	var time: CMTime
	var image: CIImage
}

protocol VideoFrameSource: AnyObject, Sendable {
	var frames: any AsyncSequence<VideoFrame, Never> { get }
}

final class NDIVideoFrameSource: VideoFrameSource, Sendable {
	private let _clock = Dependency(\.hostTimeClock)
	let player: NDIPlayer

	init(player: NDIPlayer) {
		self.player = player
	}

	var frames: any AsyncSequence<VideoFrame, Never> {
		let clock = _clock.wrappedValue

		return player.videoFrames.compactMap { [clock] frame -> VideoFrame? in
			guard let pixelBuffer = frame.pixelBuffer else { return nil }
			let image = CIImage(cvPixelBuffer: pixelBuffer)

			let time = clock.convert(frame.timestamp)

			return VideoFrame(
				time: time,
				image: image
			)
		}
	}
}

extension CMClock {
	func convert(_ timestamp: Date?) -> CMTime {
		// convert world clock timestamp to host media clock by subtracting the diff from our current time
		@Dependency(\.date.now) var date
		let time = self.time

		guard let timestamp else { return time }

		let diff = date.timeIntervalSince(timestamp)

		return time - CMTime(seconds: diff, preferredTimescale: 10_000_000)
	}
}
