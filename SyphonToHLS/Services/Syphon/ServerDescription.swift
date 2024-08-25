import Cocoa
import Syphon

struct ServerDescription: Identifiable {
	var description: [String: Any]

	var id: String
	var appName: String
	var name: String
	var icon: NSImage?

	init?(description: Any) {
		guard
			let description = description as? [String: Any],
			let id = description[SyphonServerDescriptionUUIDKey] as? String,
			let appName = description[SyphonServerDescriptionAppNameKey] as? String,
			let name = description[SyphonServerDescriptionNameKey] as? String
		else {
			assertionFailure()
			return nil
		}

		self.description = description

		self.id = id
		self.appName = appName
		self.name = name
		self.icon = description[SyphonServerDescriptionIconKey] as? NSImage
	}
}
