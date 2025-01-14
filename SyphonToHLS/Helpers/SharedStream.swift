import ConcurrencyExtras
import Foundation

final class SharedStream<Element: Sendable>: AsyncSequence, Sendable {
	private let continuations: LockIsolated<[AsyncStream<Element>.Continuation]> = .init([])

	init<Sequence: AsyncSequence & Sendable>(_ upstream: Sequence) where Sequence.Element == Element {
		Task {
			do {
				for try await element in upstream {
					let continuations = self.continuations.value

					for continuation in continuations {
						continuation.yield(element)
					}
				}

				let continuations = self.continuations.value
				for continuation in continuations {
					continuation.finish()
				}
			} catch {
				let continuations = self.continuations.value
				for continuation in continuations {
					continuation.finish()
				}
			}
		}
	}

	func makeAsyncIterator() -> AsyncStream<Element>.AsyncIterator {
		let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
		continuations.withValue { $0.append(continuation) }

		return stream.makeAsyncIterator()
	}
}

extension AsyncSequence where Element: Sendable, Self: Sendable {
	func share() -> SharedStream<Element> {
		SharedStream(self)
	}
}
