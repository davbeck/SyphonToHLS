import Foundation

public extension Date {
	init?(ndiTimestamp timestamp: Int64) {
		guard timestamp != NDIlib_recv_timestamp_undefined else { return nil }
		self.init(timeIntervalSince1970: TimeInterval(timestamp) / TimeInterval(NDI.timescale))
	}
}
