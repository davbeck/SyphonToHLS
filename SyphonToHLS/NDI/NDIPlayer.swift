import Foundation

actor NDIPlayer {
	private var receiver: NDIReceiver?

	let sourceName: String
	private var source: NDISource?

	init(name: String) {
		self.sourceName = name
	}

	init(source: NDISource) {
		self.sourceName = source.name
		self.source = source
	}

	private func getReceiver() async -> NDIReceiver? {
		if let receiver {
			return receiver
		} else if let source {
			guard let receiver = NDIReceiver(source: source) else { return nil }

			self.receiver = receiver
			return receiver
		} else {
			guard let receiver = NDIReceiver() else { return nil }

			await receiver.connect(name: sourceName)

			self.receiver = receiver
			return receiver
		}
	}

	private var lastVideoFrame: NDIVideoFrame?

	private func receive(types: Set<NDICaptureType>) async {
		guard let receiver = await getReceiver() else { return }

		while !Task.isCancelled {
			let frame = receiver.capture(types: types)

			switch frame {
			case let .video(frame):
				lastVideoFrame = frame
				for (_, continuation) in videoFramesContinuations {
					continuation.yield(frame)
				}
			default:
				break
			}

			await Task.yield()
		}
	}

	var isConnected: Bool {
		receiver != nil
	}

	func connect() async -> Bool {
		await getReceiver() != nil
	}

	// MARK: - Video

	typealias VideoFrameStream = AsyncStream<NDIVideoFrame>

	private var videoFramesTask: Task<Void, Never>? {
		didSet {
			oldValue?.cancel()
		}
	}

	private var videoFramesContinuations: [UUID: VideoFrameStream.Continuation] = [:] {
		didSet {
			if videoFramesContinuations.isEmpty {
				videoFramesTask = nil
			} else if videoFramesTask == nil || videoFramesTask?.isCancelled == true {
				videoFramesTask = Task {
					await self.receive(types: [.video])
				}
			}
		}
	}

	private func registerVideoContinuation(_ continuation: VideoFrameStream.Continuation) {
		if let lastVideoFrame {
			continuation.yield(lastVideoFrame)
		}

		let id = UUID()
		videoFramesContinuations[id] = continuation

		continuation.onTermination = { reason in
			Task {
				await self.unregisterVideoContinuation(id)
			}
		}
	}

	private func unregisterVideoContinuation(_ id: UUID) {
		self.videoFramesContinuations.removeValue(forKey: id)
	}

	nonisolated
	var videoFrames: VideoFrameStream {
		let (stream, continuation) = VideoFrameStream.makeStream(bufferingPolicy: .bufferingNewest(1))

		Task {
			await self.registerVideoContinuation(continuation)
		}

		return stream
	}
}
