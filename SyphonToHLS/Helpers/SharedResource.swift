import ConcurrencyExtras

final class SharedResource<Value> {
	private let generate: () -> Value
	private var resource: Value?

	private var accessors: [Weak<Accessor>] = []

	init(generate: @escaping () -> Value) {
		self.generate = generate
	}

	func get() -> Accessor {
		let resource: Value
		if let existing = self.resource {
			resource = existing
		} else {
			resource = generate()

			self.resource = resource
		}

		let accessor = Accessor(
			value: resource,
			sharedResource: self
		)

		accessors.append(Weak(value: accessor))

		return accessor
	}

	private func deregister(_ accessor: Accessor) {
		accessors.removeAll(where: {
			$0.value == nil || $0.value === accessor
		})

		if accessors.isEmpty {
			resource = nil
		}
	}

	@dynamicMemberLookup
	final class Accessor {
		let value: Value
		private let sharedResource: SharedResource

		init(value: Value, sharedResource: SharedResource) {
			self.value = value
			self.sharedResource = sharedResource
		}

		deinit {
			sharedResource.deregister(self)
		}

		subscript<T>(dynamicMember dynamicMember: KeyPath<Value, T>) -> T {
			value[keyPath: dynamicMember]
		}

		subscript<T>(dynamicMember dynamicMember: ReferenceWritableKeyPath<Value, T>) -> T {
			get {
				value[keyPath: dynamicMember]
			}
			set {
				value[keyPath: dynamicMember] = newValue
			}
		}
	}
}

struct Weak<Value: AnyObject> {
	weak var value: Value?
}
