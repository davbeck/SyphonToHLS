import ConcurrencyExtras
import Foundation

actor NDIPlayer {
	private static var playerPool: LockIsolated<[String: Weak<NDIPlayer>]> = .init([:])

	static func player(for name: String) -> NDIPlayer {
		playerPool.withValue { pool in
			if let player = pool[name]?.value {
				return player
			} else {
				let player = NDIPlayer(name: name)
				pool[name] = .init(value: player)
				return player
			}
		}
	}

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
			case let .audio(frame):
				for (_, continuation) in audioFramesContinuations {
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

	// MARK: - Audio

	typealias AudioFrameStream = AsyncStream<NDIAudioFrame>

	private var audioFramesTask: Task<Void, Never>? {
		didSet {
			oldValue?.cancel()
		}
	}

	private var audioFramesContinuations: [UUID: AudioFrameStream.Continuation] = [:] {
		didSet {
			if audioFramesContinuations.isEmpty {
				audioFramesTask = nil
			} else if audioFramesTask == nil || audioFramesTask?.isCancelled == true {
				audioFramesTask = Task {
					await self.receive(types: [.audio])
				}
			}
		}
	}

	private func registerAudioContinuation(_ continuation: AudioFrameStream.Continuation) {
		let id = UUID()
		audioFramesContinuations[id] = continuation

		continuation.onTermination = { reason in
			Task {
				await self.unregisterAudioContinuation(id)
			}
		}
	}

	private func unregisterAudioContinuation(_ id: UUID) {
		self.audioFramesContinuations.removeValue(forKey: id)
	}

	nonisolated
	var audioFrames: AudioFrameStream {
		let (stream, continuation) = AudioFrameStream.makeStream(bufferingPolicy: .bufferingNewest(1))

		Task {
			await self.registerAudioContinuation(continuation)
		}

		return stream
	}
}
