import AVFoundation
import Combine
import Observation

@Observable
@MainActor
final class AudioSourceService {
	static let shared = AudioSourceService()

	let discoverySession: AVCaptureDevice.DiscoverySession

	var devices: [AVCaptureDevice] = []

	private var observers: Set<AnyCancellable> = []

	init() {
		self.discoverySession = AVCaptureDevice.DiscoverySession(
			deviceTypes: [.microphone],
			mediaType: .audio,
			position: .unspecified
		)

		self.devices = discoverySession.devices
		self.discoverySession.publisher(for: \.devices)
			.sink { [weak self] devices in
				Task { @MainActor in
					self?.devices = devices
				}
			}
			.store(in: &observers)
	}
}
