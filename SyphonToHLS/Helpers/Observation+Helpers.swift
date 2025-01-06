import Foundation
import Observation

@MainActor
public func withObservationTracking<T>(_ apply: () -> T, onChanged: @escaping @MainActor () -> Void) -> T {
	withObservationTracking {
		apply()
	} onChange: {
		RunLoop.main.perform {
			MainActor.assumeIsolated {
				onChanged()
			}
		}
	}
}

@MainActor
func withObservationTracking(_ apply: @escaping @MainActor () -> Void) {
	withObservationTracking {
		apply()
	} onChanged: {
		withObservationTracking(apply)
	}
}
