import Foundation

struct Config: Codable {
	var schedule: Schedule = .init()
}

extension Config {
	struct Schedule: Codable {
		var weekdays: [Int] = [1]
		var startHour: Int = 9
		var startMinute: Int = 50
		var duration: Duration = .hours(2)

		var startingDateComponents: [DateComponents] {
			self.weekdays
				.map { DateComponents(hour: startHour, minute: startMinute, weekday: $0) }
		}
	}
}
