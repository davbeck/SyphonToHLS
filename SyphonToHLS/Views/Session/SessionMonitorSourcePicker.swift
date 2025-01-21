import AVFoundation
import Dependencies
import Sharing
import SimplyCoreAudio
import SwiftUI

struct SessionMonitorSourcePicker: View {
	typealias Selection = String?

	@Shared(.monitorDeviceID) private var monitorDeviceID
	let audioOutputService = AudioOutputService.shared

	var body: some View {
		Picker("Audio Monitor", selection: Binding($monitorDeviceID)) {
			Text("None")
				.tag(Selection.none)

			if
				let monitorDeviceID,
				!monitorDeviceID.isEmpty &&
				!audioOutputService.devices.contains(where: { $0.uid == monitorDeviceID })
			{
				Group {
					if let device = AudioDevice.lookup(by: monitorDeviceID) {
						Text("\(device.name) (Disconnected)")
					} else {
						Text("\(monitorDeviceID) (Disconnected)")
					}
				}
				.tag(Selection.some(monitorDeviceID))
			}

			ForEach(audioOutputService.devices.filter { $0.uid != nil }, id: \.uid) { device in
				Text(device.name)
					.tag(device.uid as Selection)
			}
		}
	}
}

#Preview {
	SessionAudioSourcePicker()
}
