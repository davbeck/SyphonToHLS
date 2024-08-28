import CoreMedia

struct HLSRecord {
	var index: Int
	var duration: CMTime

	var name: String {
		"\(index).m4s"
	}
}

extension Collection where Element == HLSRecord {
	func hlsPlaylist() -> String {
		let segmentTemplate = self
			.map { record in
				"""
				#EXTINF:\(record.duration.seconds),
				\(record.name)
				"""
			}
			.joined(separator: "\n")

		let startSequence = self.first?.index ?? 1

		return """
		#EXTM3U
		#EXT-X-TARGETDURATION:10
		#EXT-X-VERSION:9
		#EXT-X-MEDIA-SEQUENCE:\(startSequence)
		#EXT-X-MAP:URI="0.mp4"
		\(segmentTemplate)
		"""
	}
}
