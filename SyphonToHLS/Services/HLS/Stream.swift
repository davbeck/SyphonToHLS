import CoreGraphics

enum VideoQualityLevel: CaseIterable {
	case high // 1080 7.5mbps
	case medium // 720 3.8mbps
	case low // 360 350kbps

	var resolutions: CGSize {
		switch self {
		case .high:
			CGSize(width: 1920, height: 1080)
		case .medium:
			CGSize(width: 1280, height: 720)
		case .low:
			CGSize(width: 640, height: 360)
		}
	}

	var name: String {
		switch self {
		case .high:
			"high"
		case .medium:
			"medium"
		case .low:
			"low"
		}
	}

	var bitrate: Int {
		switch self {
		case .high:
			Int(7.5 * 1024 * 1024)
		case .medium:
			Int(3.8 * 1024 * 1024)
		case .low:
			Int(350 * 1024)
		}
	}
}

enum Stream: Hashable, CaseIterable {
	case video(VideoQualityLevel)
	case audio

	static var allCases: [Stream] {
		VideoQualityLevel.allCases.map { Stream.video($0) } + [.audio]
	}

	var header: String {
		switch self {
		case let .video(quality):
			quality.name
		case .audio:
			"audio"
		}
	}
}
