import Foundation
import MetaCodable
import Sharing

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

extension SharedKey where Self == FileStorageKey<VideoSource?>.Default {
	static var videoSource: Self {
		Self[.configStorage(name: "videoSource"), default: nil]
	}
}

extension SharedKey where Self == FileStorageKey<AudioSource?>.Default {
	static var audioSource: Self {
		Self[.configStorage(name: "audioSource"), default: nil]
	}
}

extension SharedKey where Self == FileStorageKey<String?>.Default {
	static var monitorDeviceID: Self {
		Self[.configStorage(name: "monitorDeviceID"), default: nil]
	}
}

extension SharedKey where Self == FileStorageKey<ScheduleConfig>.Default {
	static var scheduleConfig: Self {
		Self[.configStorage(name: "schedule"), default: ScheduleConfig()]
	}
}

struct ScheduleConfig: Codable {
	var weekdays: [Int] = [1]
	var startHour: Int = 9
	var startMinute: Int = 50
	var duration: Duration = .hours(2) + .minutes(10)

	var startingDateComponents: [DateComponents] {
		self.weekdays
			.map { DateComponents(hour: startHour, minute: startMinute, weekday: $0) }
	}
}

extension SharedKey where Self == FileStorageKey<AWSConfig>.Default {
	static var awsConfig: Self {
		Self[.configStorage(name: "aws"), default: AWSConfig()]
	}
}

struct AWSConfig: Codable {
	var region: String = ""
	var bucket: String = ""
	var clientKey: String = ""
	var clientSecret: String = ""
}

extension SharedKey where Self == FileStorageKey<EncoderConfig>.Default {
	static var encoderConfig: Self {
		Self[.configStorage(name: "encoder"), default: EncoderConfig()]
	}
}

@Codable
@MemberInit
struct EncoderConfig {
	@Default(6)
	var preferredOutputSegmentInterval: Double

	@Default(Set(VideoQualityLevel.allCases))
	var qualityLevels: Set<VideoQualityLevel>

	init() {
		self.init(preferredOutputSegmentInterval: 6)
	}
}
