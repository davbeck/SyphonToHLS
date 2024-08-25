import Cocoa
import Combine
import Metal
import Syphon

class SyphonMetalClient: Syphon.SyphonMetalClient {
	let frames: AsyncStream<any MTLTexture>

	init(
		_ serverDescription: ServerDescription,
		device: any MTLDevice,
		options: [AnyHashable: Any]? = nil
	) {
		let (stream, continuation) = AsyncStream.makeStream(of: MTLTexture.self)

		self.frames = stream

		super.init(
			serverDescription: serverDescription.description,
			device: device,
			options: options,
			newFrameHandler: { client in
				guard let texture = client.newFrameImage() else { return }

				continuation.yield(texture)
			}
		)
	}
}
