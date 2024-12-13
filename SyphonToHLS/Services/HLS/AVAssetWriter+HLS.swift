import AVFoundation

extension AVAssetWriter {
	static func hlsWriter() -> AVAssetWriter {
		let assetWriter = AVAssetWriter(contentType: .mpeg4Movie)

		assetWriter.shouldOptimizeForNetworkUse = true
		assetWriter.outputFileTypeProfile = .mpeg4AppleHLS
		assetWriter.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 1)

		return assetWriter
	}
}

enum HLSAssetWriterError: Swift.Error {
	case notStarted
	case invalidWriterStatus(AVAssetWriter.Status)
}
