import Foundation

extension URL {
	static let configDirectory: URL = {
		let url = URL
			.homeDirectory
			.appending(component: ".config")
			.appending(component: "SyphonToHLS")

		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

		return url
	}()
}
