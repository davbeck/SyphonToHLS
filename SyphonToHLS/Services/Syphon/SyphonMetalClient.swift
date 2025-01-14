import Cocoa
import Combine
import CoreImage
import CoreMedia
import Metal
@preconcurrency import Syphon

final class SyphonCoreImageClient: Sendable {
	struct Frame: @unchecked Sendable {
		var time: CMTime
		var image: CIImage
	}

	private let metalClient: SyphonMetalClient
	let clock = CMClock.hostTimeClock
	let frames: SharedStream<Frame>

	init(
		_ serverDescription: ServerDescription,
		device: any MTLDevice,
		options: [AnyHashable: Any]? = nil
	) {
		let (stream, continuation) = AsyncStream.makeStream(of: Frame.self)
		self.frames = stream.share()

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

				continuation.yield(Frame(time: time, image: image))
			}
		)
	}
}
