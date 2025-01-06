import Dependencies
import Foundation
import Logging
import Observation

@MainActor
@Observable
final class ConfigManager {
	let logger = Logger(label: "Config")

	let decoder = JSONDecoder()
	let encoder = JSONEncoder()

	let url: URL?
	var config: Config {
		didSet {
			if let url {
				do {
					let data = try encoder.encode(config)
					try data.write(to: url)
				} catch {
					logger.error("failed to save config: \(error)")
				}
			}
		}
	}

	nonisolated
	init(url: URL?) {
		self.url = url

		decoder.allowsJSON5 = true

		encoder.outputFormatting = [.prettyPrinted]

		if let url {
			do {
				let data = try Data(contentsOf: url)
				self._config = try decoder.decode(Config.self, from: data)
			} catch CocoaError.fileReadNoSuchFile {
				self._config = Config()

				do {
					let data = try encoder.encode(self._config)
					try data.write(to: url)
				} catch {
					logger.error("failed to save config: \(error)")
				}
			} catch {
				logger.error("failed to load config: \(error)")

				self._config = Config()
			}
		} else {
			self._config = Config()
		}
	}
}

extension ConfigManager: DependencyKey {
	nonisolated
	static let liveValue = ConfigManager(url: URL.configDirectory.appending(component: "Config.json"))
}

extension DependencyValues {
	var configManager: ConfigManager {
		get { self[ConfigManager.self] }
		set { self[ConfigManager.self] = newValue }
	}
}
