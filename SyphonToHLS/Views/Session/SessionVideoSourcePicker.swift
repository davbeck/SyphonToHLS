import Dependencies
import Sharing
import SwiftUI

struct SessionVideoSourcePicker: View {
	@Shared(.videoSource) private var videoSource

	private let session = ProfileSession.liveValue

	@State private var finder = NDIFindManager.shared

	var ndiSources: [NDISource] {
		finder?.sources ?? []
	}

	var body: some View {
		Picker("Video Source", selection: Binding($videoSource)) {
			Text("None")
				.tag(VideoSource?.none)

			Section("Syphon") {
				if
					let syphonServerID = videoSource?.syphonID,
					!session.syphonService.servers.contains(where: { $0.id == syphonServerID })
				{
					Text("\(syphonServerID.appName) - \(syphonServerID.name) (Unavailable)")
						.tag(Optional.some(VideoSource.syphon(id: syphonServerID)))
						.disabled(true)
				}

				ForEach(session.syphonService.servers) { server in
					Text("\(server.id.appName) - \(server.id.name)")
						.tag(Optional.some(VideoSource.syphon(id: server.id)))
				}
			}

			Section("NDI") {
				if
					let ndiName = videoSource?.ndiName,
					!ndiSources.contains(where: { $0.name == ndiName })
				{
					Text("\(ndiName) (Unavailable)")
						.tag(Optional.some(VideoSource.ndi(name: ndiName)))
						.disabled(true)
				}

				ForEach(ndiSources, id: \.self) { source in
					Text(source.name)
						.tag(Optional.some(VideoSource.ndi(name: source.name)))
				}
			}
		}
	}
}

#Preview {
	SessionVideoSourcePicker()
}
