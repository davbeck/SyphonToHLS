import Cocoa
import Combine
import CoreMedia
import Metal
import Syphon

class SyphonMetalClient: Syphon.SyphonMetalClient {
	struct Frame {
		var time: CMTime
		var texture: any MTLTexture
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
				guard let texture = client.newFrameImage() else { return }

				continuation.yield(Frame(time: time, texture: texture))
			}
		)
	}
}

final class SharedStream<Element>: AsyncSequence, @unchecked Sendable {
	private let lock = NSRecursiveLock()
	private var continuations: [AsyncStream<Element>.Continuation] = []

	init(_ upstream: some AsyncSequence<Element, Never>) {
		Task {
			for await element in upstream {
				let continuations = self.lock.withLock { self.continuations }

				for continuation in continuations {
					continuation.yield(element)
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

extension AsyncSequence where Failure == Never {
	func share() -> SharedStream<Element> {
		SharedStream(self)
	}
}
