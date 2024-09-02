import Foundation
import KeychainSwift
import Observation

struct AppStorageKey<Value: Hashable>: Hashable {
	var key: String
	var isSecure: Bool = false
	var defaultValue: Value
}

extension AppStorageKey where Value == String {
	init(key: String, isSecure: Bool = false) {
		self.init(key: key, isSecure: isSecure, defaultValue: "")
	}
}

extension AppStorageKey where Value == Bool {
	init(key: String, isSecure: Bool = false) {
		self.init(key: key, isSecure: isSecure, defaultValue: false)
	}
}

extension AppStorageKey where Value == String {
	static let awsRegion = AppStorageKey(key: "awsRegion")
	static let awsS3Bucket = AppStorageKey(key: "awsS3Bucket")
	static let awsClientKey = AppStorageKey(key: "awsClientKey")
	static let awsClientSecret = AppStorageKey(key: "awsClientSecret", isSecure: true)
}

@MainActor
final class AppStorage: Observable {
	// MARK: - Observation

	private let _$observationRegistrar = Observation.ObservationRegistrar()

	nonisolated func access(
		keyPath: KeyPath<AppStorage, some Any>
	) {
		_$observationRegistrar.access(self, keyPath: keyPath)
	}

	nonisolated func withMutation<MutationResult>(
		keyPath: KeyPath<AppStorage, some Any>,
		_ mutation: () throws -> MutationResult
	) rethrows -> MutationResult {
		try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
	}

	// MARK: - Storage

	private let defaults = UserDefaults()

	private let keychain = KeychainSwift()
	
	subscript(_ key: AppStorageKey<String>) -> String {
		get {
			access(keyPath: \.[key])
			if key.isSecure {
				return keychain.get(key.key) ?? key.defaultValue
			} else {
				return defaults.string(forKey: key.key) ?? key.defaultValue
			}
		}
		set {
			withMutation(keyPath: \.[key]) {
				if key.isSecure {
					_ = keychain.set(newValue, forKey: key.key)
				} else {
					defaults.set(newValue, forKey: key.key)
				}
			}
		}
	}
	
	subscript(_ key: AppStorageKey<Bool>) -> Bool {
		get {
			access(keyPath: \.[key])
			if key.isSecure {
				return keychain.getBool(key.key) ?? key.defaultValue
			} else {
				return defaults.bool(forKey: key.key)
			}
		}
		set {
			withMutation(keyPath: \.[key]) {
				if key.isSecure {
					_ = keychain.set(newValue, forKey: key.key)
				} else {
					defaults.set(newValue, forKey: key.key)
				}
			}
		}
	}

	init() {}

	static let shared = AppStorage()
}
