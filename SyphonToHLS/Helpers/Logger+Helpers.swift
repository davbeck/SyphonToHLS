import OSLog

extension Logger {
	init(category: String) {
		self.init(
			subsystem: Bundle(for: ProfileSession.self).bundleIdentifier ?? "",
			category: category
		)
	}
}
