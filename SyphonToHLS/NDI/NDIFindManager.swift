import ConcurrencyExtras
import Dependencies
import Observation
import Synchronization

@MainActor
@Observable
final class NDIFindManager {
	private static let _shared = Mutex(Weak<NDIFindManager>())
	static var shared: NDIFindManager? {
		_shared.withLock { box in
			if let value = box.value {
				return value
			} else if let value = NDIFindManager() {
				box.value = value

				return value
			} else {
				return nil
			}
		}
	}

	@ObservationIgnored
	@Dependency(\.continuousClock) private var clock

	private let instance: NDIFind

	var sources: [NDISource] = []

	init?() {
		guard let instance = NDIFind() else {
			return nil
		}

		self.instance = instance

		self.sources = instance.getCurrentSources()
		Task { [weak self] in
			while !Task.isCancelled {
				guard let self else { return }
				if instance.waitForSources(timeout: .zero) {
					self.sources = instance.getCurrentSources()
				}

				try? await clock.sleep(for: .milliseconds(100))
			}
		}
	}
}
