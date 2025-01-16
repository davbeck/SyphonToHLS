import Dependencies
import Observation

class NDIFind: @unchecked Sendable {
	let ndi: NDI

	private let pNDI_find: NDIlib_find_instance_t

	convenience init?() {
		guard let ndi = NDI.shared else {
			return nil
		}

		self.init(ndi: ndi)
	}

	init?(ndi: NDI) {
		self.ndi = ndi

		guard let pNDI_find = NDIlib_find_create_v2(nil) else {
			assertionFailure("NDIlib_find_create_v2 failed")
			return nil
		}

		self.pNDI_find = pNDI_find
	}

	deinit {
		NDIlib_find_destroy(pNDI_find)
	}

	func waitForSources(timeout: Duration = .zero) -> Bool {
		NDIlib_find_wait_for_sources(pNDI_find, UInt32(timeout.seconds * 1000))
	}

	func getCurrentSources() -> [NDISource] {
		var no_sources: UInt32 = 0
		guard let p_sources = NDIlib_find_get_current_sources(pNDI_find, &no_sources) else {
			assertionFailure("NDIlib_find_get_current_sources failed")
			return []
		}

		return (0 ..< no_sources).compactMap { i in
			NDISource(p_sources[Int(i)], find: self)
		}
	}

	func getSource(named name: String) async -> NDISource? {
		while !Task.isCancelled {
			if waitForSources() {
				let sources = getCurrentSources()

				if let source = sources.first(where: { $0.name == name }) {
					return source
				}
			}

			await Task.yield()
		}

		return nil
	}
}
