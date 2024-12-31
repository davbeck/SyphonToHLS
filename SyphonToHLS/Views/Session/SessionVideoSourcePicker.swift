import Dependencies
import SwiftUI

struct SessionVideoSourcePicker: View {
	@Dependency(\.profileSession) private var session
	@State private var appStorage = AppStorage.shared

	var body: some View {
		Picker("Video Source", selection: Bindable(session).syphonServerID) {
			Text("None")
				.tag(ServerDescription.ID?.none)

			if let syphonServerID = session.syphonServerID, !session.syphonService.servers.contains(where: { $0.id == syphonServerID }) {
				Text("\(appStorage[.syphonServerApp]) - \(appStorage[.syphonServerName]) (Unavailable)")
					.tag(Optional.some(syphonServerID))
					.disabled(true)
			}

			ForEach(session.syphonService.servers) { server in
				Text("\(server.id.appName) - \(server.id.name)")
					.tag(Optional.some(server.id))
			}
		}
	}
}

#Preview {
	SessionVideoSourcePicker()
}
