import Observation
import Dependencies

@MainActor
@Observable
final class NDIFindManager {
	@ObservationIgnored
	@Dependency(\.continuousClock) private var clock

	private let instance: NDIFind

	var sources: [NDISource] = []

	init?() {
		guard let instance = NDIFind() else {
			return nil
		}

		self.instance = instance
	}

	func start() async {
		self.sources = instance.getCurrentSources()

		while !Task.isCancelled {
			if instance.waitForSources(timeout: .zero) {
				self.sources = instance.getCurrentSources()
			}

			try? await clock.sleep(for: .milliseconds(100))
		}
	}
}
