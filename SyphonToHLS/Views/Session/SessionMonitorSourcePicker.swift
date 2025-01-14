import AVFoundation
import Dependencies
import SimplyCoreAudio
import SwiftUI

struct SessionMonitorSourcePicker: View {
	private let session = ProfileSession.liveValue

	var body: some View {
		Picker("Audio Monitor", selection: Bindable(session).monitorDeviceUID) {
			Text("None")
				.tag("")

			if !session.monitorDeviceUID.isEmpty && !session.audioOutputService.devices.contains(where: { $0.uid == session.monitorDeviceUID }) {
				Group {
					if let device = AudioDevice.lookup(by: session.monitorDeviceUID) {
						Text("\(device.name) (Disconnected)")
					} else {
						Text("\(session.monitorDeviceUID) (Disconnected)")
					}
				}
				.tag(session.monitorDeviceUID)
			}

			ForEach(session.audioOutputService.devices.filter { $0.uid != nil }, id: \.uid) { device in
				Text(device.name)
					.tag(device.uid ?? "")
			}
		}
	}
}

#Preview {
	SessionAudioSourcePicker()
}
