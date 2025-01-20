import AVFoundation
import VideoToolbox

extension AVAssetWriter {
	static func hlsWriter(preferredOutputSegmentInterval: Double) -> AVAssetWriter {
		let assetWriter = AVAssetWriter(contentType: .mpeg4Movie)

		assetWriter.shouldOptimizeForNetworkUse = true
		assetWriter.outputFileTypeProfile = .mpeg4AppleHLS
		assetWriter.preferredOutputSegmentInterval = CMTime(
			seconds: preferredOutputSegmentInterval,
			preferredTimescale: 1
		)

		return assetWriter
	}

	struct AssetWriterStatusError: Error {
		var status: AVAssetWriter.Status
	}

	func checkWritable() throws {
		let status = self.status
		switch status {
		case .unknown:
			throw HLSAssetWriterError.invalidWriterStatus(status)
		case .cancelled:
			throw CancellationError()
		case .failed:
			throw self.error ?? HLSAssetWriterError.invalidWriterStatus(status)
		case .completed:
			throw HLSAssetWriterError.invalidWriterStatus(status)
		case .writing:
			return
		@unknown default:
			throw HLSAssetWriterError.invalidWriterStatus(status)
		}
	}
}

enum HLSAssetWriterError: Swift.Error {
	case notStarted
	case invalidWriterStatus(AVAssetWriter.Status)
}

extension AVAssetWriterInput {
	static func hlsAudioInput() -> AVAssetWriterInput {
		let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
			AVFormatIDKey: kAudioFormatMPEG4AAC,

			AVSampleRateKey: 48000,
			AVNumberOfChannelsKey: 1,
			AVEncoderBitRateKey: 80 * 1024,
		])
		input.expectsMediaDataInRealTime = true
		return input
	}

	static func hlsVideoInput(quality: VideoQualityLevel) -> AVAssetWriterInput {
		let videoInput = AVAssetWriterInput(
			mediaType: .video,
			outputSettings: [
				AVVideoCodecKey: AVVideoCodecType.h264,
				AVVideoWidthKey: quality.resolutions.width,
				AVVideoHeightKey: quality.resolutions.height,

				AVVideoCompressionPropertiesKey: [
					kVTCompressionPropertyKey_AverageBitRate: quality.bitrate,
					kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_4_1,
				],
			]
		)
		videoInput.expectsMediaDataInRealTime = true

		return videoInput
	}
}
