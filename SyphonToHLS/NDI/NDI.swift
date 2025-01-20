import OSLog

actor NDI {
	static let shared: NDI? = NDI()

	let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "ndi")

	init?() {
		// Not required, but "correct" (see the SDK documentation).
		if !NDIlib_initialize() {
			assertionFailure("failed NDIlib_initialize")
			return nil
		}
		logger.debug("NDIlib_initialize")
	}

	deinit {
		// Finished
		NDIlib_destroy()
		logger.debug("NDIlib_destroy")
	}

	/// The units that time is represented in (100ns) per second
	static let timescale: Int64 = 10_000_000
}
