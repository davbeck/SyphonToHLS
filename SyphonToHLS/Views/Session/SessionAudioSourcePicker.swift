import AVFoundation
import SwiftUI

struct SessionAudioSourcePicker: View {
	@State private var session = ProfileSession.shared
	@State private var appStorage = AppStorage.shared

	var body: some View {
		Picker("Audio Source", selection: $session.audioDevice) {
			Text("None")
				.tag(AVCaptureDevice?.none)

			if let device = session.audioDevice, !session.audioSourceService.devices.contains(where: { $0.uniqueID == device.uniqueID }) {
				Text("\(device.localizedName) (Disconnected)")
					.tag(Optional.some(device))
			}

			ForEach(session.audioSourceService.devices, id: \.uniqueID) { device in
				Text(device.localizedName)
					.tag(Optional.some(device))
			}
		}
	}
}

#Preview {
	SessionAudioSourcePicker()
}
