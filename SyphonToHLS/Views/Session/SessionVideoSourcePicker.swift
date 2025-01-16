import Dependencies
import SwiftUI

struct SessionVideoSourcePicker: View {
	@Dependency(\.configManager) private var configManager

	private let session = ProfileSession.liveValue

	@State private var finder = NDIFindManager()

	var ndiSources: [NDISource] {
		finder?.sources ?? []
	}

	var body: some View {
		@Bindable var configManager = self.configManager

		Picker("Video Source", selection: $configManager.config.videoSource) {
			Text("None")
				.tag(VideoSource?.none)

			Section("Syphon") {
				if let syphonServerID = configManager.config.videoSource?.syphonID, !session.syphonService.servers.contains(where: { $0.id == syphonServerID }) {
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
				if let ndiName = configManager.config.videoSource?.ndiName, !ndiSources.contains(where: { $0.name == ndiName }) {
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
		.task {
			await finder?.start()
		}
	}
}

#Preview {
	SessionVideoSourcePicker()
}
