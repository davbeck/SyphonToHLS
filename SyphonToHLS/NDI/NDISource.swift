struct NDISource: Hashable {
	// referenced to keep ref alive
	private let find: NDIFind

	internal var ref: NDIlib_source_t

	init?(_ ref: NDIlib_source_t, find: NDIFind) {
		self.ref = ref
		self.find = find
	}

	var name: String {
		String(cString: ref.p_ndi_name)
	}

	var url: String {
		String(cString: ref.p_url_address)
	}

	static func == (lhs: NDISource, rhs: NDISource) -> Bool {
		lhs.ref.p_ndi_name == rhs.ref.p_ndi_name && lhs.ref.p_url_address == rhs.ref.p_url_address
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(ref.p_ndi_name)
		hasher.combine(ref.p_url_address)
	}
}

extension NDISource: Identifiable {
	var id: String { String(cString: ref.p_url_address) }
}
