import Cocoa
import Combine
import CoreImage
import CoreMedia

@preconcurrency import Metal

@preconcurrency import Syphon

final class SyphonCoreImageClient: Sendable, VideoFrameSource {
	let device: any MTLDevice
	private let metalClient: SyphonMetalClient
	let clock = CMClock.hostTimeClock
	private let _frames: SharedStream<VideoFrame>

	var frames: any AsyncSequence<VideoFrame, Never> {
		_frames
	}

	let serverDescription: ServerDescription

	init(
		_ serverDescription: ServerDescription,
		device: any MTLDevice,
		options: [AnyHashable: Any]? = nil
	) {
		self.device = device
		self.serverDescription = serverDescription

		let (stream, continuation) = AsyncStream.makeStream(of: VideoFrame.self)
		self._frames = stream.share()

		self.metalClient = SyphonMetalClient(
			serverDescription: serverDescription.description,
			device: device,
			options: options,
			newFrameHandler: { [clock] client in
				let time = clock.time
				guard
					let texture = client.newFrameImage(),
					let image = CIImage(
						mtlTexture: texture,
						options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]
					)
				else { return }

				continuation.yield(VideoFrame(time: time, image: image))
			}
		)
	}
}
