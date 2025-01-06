import Foundation
import MetaCodable

@Codable
@MemberInit
struct Config {
	@Default(Schedule())
	var schedule: Schedule

	var syphonServerID: ServerDescription.ID?
	@Default("")
	var audioDeviceID: String
	@Default("")
	var monitorDeviceID: String

	@Default(AWS())
	var aws: AWS
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

extension Config {
	struct AWS: Codable {
		var region: String = ""
		var bucket: String = ""
		var clientKey: String = ""
		var clientSecret: String = ""
	}
}
