import AVFoundation
import Dependencies
import Sharing
import SwiftUI

struct SessionAudioSourcePicker: View {
	@Shared(.audioSource) private var audioSource
	private let session = ProfileSession.liveValue

	@State private var audioSourceService = AudioSourceService()
	@State private var finder = NDIFindManager.shared

	var ndiSources: [NDISource] {
		finder?.sources ?? []
	}

	var body: some View {
		Picker("Audio Source", selection: Binding($audioSource)) {
			Text("None")
				.tag(AudioSource?.none)

			Section("Inputs") {
				if
					case let .audioDevice(id: deviceID) = audioSource,
					!audioSourceService.devices.contains(where: { $0.uniqueID == deviceID }),
					let device = audioSourceService.device(withID: deviceID)
				{
					Text("\(device.localizedName) (Disconnected)")
						.tag(Optional.some(AudioSource.audioDevice(id: deviceID)))
				}

				ForEach(audioSourceService.devices, id: \.uniqueID) { device in
					Text(device.localizedName)
						.tag(Optional.some(AudioSource.audioDevice(id: device.uniqueID)))
				}
			}

			Section("NDI") {
				if let ndiName = audioSource?.ndiName, !ndiSources.contains(where: { $0.name == ndiName }) {
					Text("\(ndiName) (Unavailable)")
						.tag(Optional.some(AudioSource.ndi(name: ndiName)))
						.disabled(true)
				}

				ForEach(ndiSources, id: \.self) { source in
					Text(source.name)
						.tag(Optional.some(AudioSource.ndi(name: source.name)))
				}
			}
		}
	}
}

#Preview {
	SessionAudioSourcePicker()
}
