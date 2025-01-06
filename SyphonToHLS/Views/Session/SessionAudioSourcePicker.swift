import AVFoundation
import SwiftUI
import Dependencies

struct SessionAudioSourcePicker: View {
	@Dependency(\.profileSession) private var session

	var body: some View {
		Picker("Audio Source", selection: Bindable(session).audioDevice) {
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
