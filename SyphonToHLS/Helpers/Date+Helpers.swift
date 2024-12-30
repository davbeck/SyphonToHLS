import Foundation

extension Date {
	func timeIntervalUntil(_ date: Date) -> TimeInterval {
		-timeIntervalSince(date)
	}
}
