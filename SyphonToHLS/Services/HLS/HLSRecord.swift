import CoreMedia

struct HLSRecord {
	var index: Int
	var duration: CMTime

	var name: String {
		"\(index).m4s"
	}
}

extension Collection where Element == HLSRecord {
	func hlsPlaylist(prefix: String?) -> String {
		let prefix = if let prefix {
			prefix + "/"
		} else {
			""
		}
		
		let segmentTemplate = self
			.map { record in
				"""
				#EXTINF:\(record.duration.seconds),
				\(prefix)\(record.name)
				"""
			}
			.joined(separator: "\n")

		let startSequence = self.first?.index ?? 1

		return """
		#EXTM3U
		#EXT-X-TARGETDURATION:6
		#EXT-X-VERSION:9
		#EXT-X-MEDIA-SEQUENCE:\(startSequence)
		#EXT-X-DISCONTINUITY-SEQUENCE:\(startSequence)
		#EXT-X-MAP:URI="\(prefix)0.mp4"
		\(segmentTemplate)
		"""
	}
}
