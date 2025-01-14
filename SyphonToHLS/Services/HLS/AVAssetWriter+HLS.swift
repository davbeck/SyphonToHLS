import AVFoundation

// TODO: make this a preference
let segmentInterval: Double = 6

extension AVAssetWriter {
	static func hlsWriter() -> AVAssetWriter {
		let assetWriter = AVAssetWriter(contentType: .mpeg4Movie)

		assetWriter.shouldOptimizeForNetworkUse = true
		assetWriter.outputFileTypeProfile = .mpeg4AppleHLS
		assetWriter.preferredOutputSegmentInterval = CMTime(
			seconds: segmentInterval,
			preferredTimescale: 1
		)

		return assetWriter
	}
}

enum HLSAssetWriterError: Swift.Error {
	case notStarted
	case invalidWriterStatus(AVAssetWriter.Status)
}
