import CoreMedia
import Dependencies

enum CMClockDependencyKey: DependencyKey {
	static var liveValue: CMClock {
		CMClock.hostTimeClock
	}
}

extension DependencyValues {
	var hostTimeClock: CMClock {
		get { self[CMClockDependencyKey.self] }
		set { self[CMClockDependencyKey.self] = newValue }
	}
}
