import AVFAudio
import CoreAudio
import Observation
import SimplyCoreAudio

// https://gist.github.com/SeanLintern/3a78b3b40ee25561eb46f4e2044f5d26

struct AudioOutputDevice: Hashable {
	var name: String?
	var uid: String?
}

@Observable
@MainActor
final class AudioOutputService {
	static let shared = AudioOutputService()

	private let coreAudio = SimplyCoreAudio()
	var devices: [AudioDevice] = []

	init() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(deviceListChanged),
			name: .deviceListChanged,
			object: nil
		)
		self.devices = coreAudio.allOutputDevices
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc nonisolated func deviceListChanged(_ notification: Notification) {
		Task { @MainActor in
			self.devices = coreAudio.allOutputDevices
		}
	}
}
