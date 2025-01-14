import AVFoundation
import Combine
import Observation
import Dependencies

@Observable
@MainActor
final class AudioSourceService {
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
