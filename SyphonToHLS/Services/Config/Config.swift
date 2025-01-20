import Foundation
import MetaCodable

enum VideoSource: Codable, Hashable {
	case syphon(id: ServerDescription.ID)
	case ndi(name: String)

	var syphonID: ServerDescription.ID? {
		switch self {
		case let .syphon(id: id):
			id
		default:
			nil
		}
	}

	var ndiName: String? {
		switch self {
		case let .ndi(name: name):
			name
		default:
			nil
		}
	}
}

enum AudioSource: Codable, Hashable {
	case audioDevice(id: String)
	case ndi(name: String)

	var audioDeviceID: String? {
		switch self {
		case let .audioDevice(id: id):
			id
		default:
			nil
		}
	}

	var ndiName: String? {
		switch self {
		case let .ndi(name: name):
			name
		default:
			nil
		}
	}
}

@Codable
@MemberInit
struct Config {
	@Default(Schedule())
	var schedule: Schedule

	@Default(VideoSource?.none)
	var videoSource: VideoSource?
	@Default(AudioSource?.none)
	var audioSource: AudioSource?
	@Default("")
	var monitorDeviceID: String

	@Default(AWS())
	var aws: AWS

	@Default(EncoderProperties())
	var encoder: EncoderProperties
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

extension Config {
	@Codable
	@MemberInit
	struct EncoderProperties {
		@Default(6)
		var preferredOutputSegmentInterval: Double

		@Default(Set(VideoQualityLevel.allCases))
		var qualityLevels: Set<VideoQualityLevel>

		init() {
			self.init(preferredOutputSegmentInterval: 6)
		}
	}
}
