import Cocoa
import Combine
import CoreImage
import CoreMedia
import Metal
import Syphon

class SyphonCoreImageClient: Syphon.SyphonMetalClient {
	struct Frame {
		var time: CMTime
		var image: CIImage
	}

	let clock = CMClock.hostTimeClock
	let frames: SharedStream<Frame>

	init(
		_ serverDescription: ServerDescription,
		device: any MTLDevice,
		options: [AnyHashable: Any]? = nil
	) {
		let (stream, continuation) = AsyncStream.makeStream(of: Frame.self)
		self.frames = stream.share()

		super.init(
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

final class SharedStream<Element>: AsyncSequence, @unchecked Sendable {
	private let lock = NSRecursiveLock()
	private var continuations: [AsyncStream<Element>.Continuation] = []

	init<Sequence: AsyncSequence>(_ upstream: Sequence) where Sequence.Element == Element {
		Task {
			do {
				for try await element in upstream {
					let continuations = self.lock.withLock { self.continuations }

					for continuation in continuations {
						continuation.yield(element)
					}
				}

				let continuations = self.lock.withLock { self.continuations }
				for continuation in continuations {
					continuation.finish()
				}
			} catch {
				let continuations = self.lock.withLock { self.continuations }
				for continuation in continuations {
					continuation.finish()
				}
			}
		}
	}

	func makeAsyncIterator() -> AsyncStream<Element>.AsyncIterator {
		let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
		lock.withLock {
			continuations.append(continuation)
		}

		return stream.makeAsyncIterator()
	}
}

extension AsyncSequence {
	func share() -> SharedStream<Element> {
		SharedStream(self)
	}
}
