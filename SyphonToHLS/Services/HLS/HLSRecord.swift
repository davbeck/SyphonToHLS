import CoreMedia

struct HLSRecord {
	var index: Int
	var discontinuityIndex: Int
	var duration: CMTime

	var name: String {
		"\(index).m4s"
	}
}

extension Collection<HLSRecord> {
	func hlsPlaylist(prefix: String?) -> String {
		let prefix = if let prefix {
			prefix + "/"
		} else {
			""
		}

		let startSequence = self.first?.index ?? 1
		let startDiscontinuity = self.first?.discontinuityIndex ?? 1

		var playlist = """
		#EXTM3U
		#EXT-X-TARGETDURATION:6
		#EXT-X-VERSION:9
		#EXT-X-MEDIA-SEQUENCE:\(startSequence)
		#EXT-X-DISCONTINUITY-SEQUENCE:\(startDiscontinuity)
		#EXT-X-MAP:URI="\(prefix)0.mp4"

		"""

		var previous: HLSRecord?
		for record in self {
			if let previous, record.discontinuityIndex != previous.discontinuityIndex {
				playlist.append("""
				#EXT-X-DISCONTINUITY

				""")
			}
			
			playlist.append("""
			#EXTINF:\(record.duration.seconds),
			\(prefix)\(record.name)
			
			""")
			
			previous = record
		}

		return playlist
	}
}
