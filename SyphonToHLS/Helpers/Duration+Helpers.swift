import Foundation

extension Duration {
	static func minutes(_ minutes: Double) -> Duration {
		.seconds(minutes * 60)
	}

	static func hours(_ hours: Double) -> Duration {
		.minutes(hours * 60)
	}

	var seconds: TimeInterval {
		TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / TimeInterval(NSEC_PER_SEC))
	}
}
