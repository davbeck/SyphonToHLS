import Foundation
import Sharing

extension SharedKey {
	static func configStorage<Value: Codable>(name: String) -> Self where Self == FileStorageKey<Value> {
		let decoder = JSONDecoder()
		decoder.allowsJSON5 = true

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted]

		return fileStorage(
			.configDirectory
				.appending(component: name)
				.appendingPathExtension(for: .json),
			decoder: decoder,
			encoder: encoder
		)
	}
}
