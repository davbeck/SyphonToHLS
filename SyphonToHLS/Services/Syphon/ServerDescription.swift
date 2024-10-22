import Cocoa
import Syphon

struct ServerDescription: Identifiable {
	struct ID: Hashable {
		var appName: String
		var name: String
	}

	var description: [String: Any]

	var id: ID
	var icon: NSImage?

	init?(description: Any) {
		guard
			let description = description as? [String: Any],
			let appName = description[SyphonServerDescriptionAppNameKey] as? String,
			let name = description[SyphonServerDescriptionNameKey] as? String
		else {
			assertionFailure()
			return nil
		}

		self.description = description

		self.id = ID(appName: appName, name: name)
		self.icon = description[SyphonServerDescriptionIconKey] as? NSImage
	}
}
