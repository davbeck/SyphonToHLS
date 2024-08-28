import Foundation
import KeychainSwift
import Observation

final class Keychain: Observable {
	// MARK: - Observation

	@ObservationIgnored private let _$observationRegistrar = Observation.ObservationRegistrar()

	nonisolated func access(
		keyPath: KeyPath<Keychain, some Any>
	) {
		_$observationRegistrar.access(self, keyPath: keyPath)
	}

	nonisolated func withMutation<MutationResult>(
		keyPath: KeyPath<Keychain, some Any>,
		_ mutation: () throws -> MutationResult
	) rethrows -> MutationResult {
		try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
	}

	// MARK: - Keychain storage

	private let keychain = KeychainSwift()

	subscript(_ key: String) -> String? {
		get {
			access(keyPath: \.[key])
			return keychain.get(key)
		}
		set {
			_ = withMutation(keyPath: \.[key]) {
				if let newValue {
					keychain.set(newValue, forKey: key)
				} else {
					keychain.delete(key)
				}
			}
		}
	}
}

final class Defaults: Observable {
	// MARK: - Observation

	@ObservationIgnored private let _$observationRegistrar = Observation.ObservationRegistrar()

	nonisolated func access(
		keyPath: KeyPath<Defaults, some Any>
	) {
		_$observationRegistrar.access(self, keyPath: keyPath)
	}

	nonisolated func withMutation<MutationResult>(
		keyPath: KeyPath<Defaults, some Any>,
		_ mutation: () throws -> MutationResult
	) rethrows -> MutationResult {
		try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
	}

	// MARK: - Keychain storage

	private let defaults = UserDefaults()

	subscript(_ key: String) -> String? {
		get {
			access(keyPath: \.[key])
			return defaults.string(forKey: key)
		}
		set {
			withMutation(keyPath: \.[key]) {
				if let newValue {
					defaults.set(newValue, forKey: key)
				} else {
					defaults.removeObject(forKey: key)
				}
			}
		}
	}
}

@Observable
@MainActor
final class AppStorage {
	private let defaults = Defaults()
	private let keychain = Keychain()

	var awsRegion: String {
		get { defaults["awsRegion"] ?? "" }
		set { defaults["awsRegion"] = newValue }
	}

	var awsS3Bucket: String {
		get { defaults["awsS3Bucket"] ?? "" }
		set { defaults["awsS3Bucket"] = newValue }
	}

	var awsClientKey: String {
		get { defaults["awsClientKey"] ?? "" }
		set { defaults["awsClientKey"] = newValue }
	}

	var awsClientSecret: String {
		get { keychain["awsClientSecret"] ?? "" }
		set { keychain["awsClientSecret"] = newValue }
	}

	init() {}
	
	static let shared = AppStorage()
}
