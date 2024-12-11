import AVFoundation
import CoreImage
import OSLog
import Queue
import VideoToolbox

actor HLSVideoService {
	enum QualityLevel: CaseIterable {
		case high // 1080 7.5mbps
		case medium // 720 3.8mbps
		case low // 360 350kbps

		var resolutions: CGSize {
			switch self {
			case .high:
				CGSize(width: 1920, height: 1080)
			case .medium:
				CGSize(width: 1280, height: 720)
			case .low:
				CGSize(width: 640, height: 360)
			}
		}

		var prefix: String {
			String(Int(resolutions.height))
		}

		var bitrate: Int {
			switch self {
			case .high:
				Int(7.5 * 1024 * 1024)
			case .medium:
				Int(3.8 * 1024 * 1024)
			case .low:
				Int(350 * 1024)
			}
		}
	}

	let syphonClient: SyphonCoreImageClient

	var writerDelegate: WriterDelegate?
	private let writers: [HLSWriter]

	private let clock = CMClock.hostTimeClock
	private let assetWriter: AVAssetWriter
	private let videoInput: AVAssetWriterInput
	private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

	private let context = CIContext()

	private let logger = Logger(category: "HLSService")

	let quality: QualityLevel

	init(url: URL, syphonClient: SyphonCoreImageClient, uploader: S3Uploader, quality: QualityLevel) {
		self.quality = quality

		self.writers = [
			HLSFileWriter(baseURL: url.appending(component: quality.prefix)),
			HLSS3Writer(uploader: uploader, prefix: quality.prefix),
		]

		self.syphonClient = syphonClient

		self.assetWriter = AVAssetWriter.hlsWriter()

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
		assetWriter.add(videoInput)

		self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
			assetWriterInput: videoInput,
			sourcePixelBufferAttributes: [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, // bgra8Unorm
				kCVPixelBufferWidthKey as String: quality.resolutions.width,
				kCVPixelBufferHeightKey as String: quality.resolutions.height,
				kCVPixelBufferMetalCompatibilityKey as String: true,
			]
		)

		self.videoInput = videoInput
	}

	func start() async throws {
		guard assetWriter.status == .unknown else { throw HLSAssetWriterError.invalidWriterStatus(assetWriter.status) }

		var start = clock.time
		let roundedSeconds = (start.seconds / 6).rounded(.up) * 6
		start = CMTime(seconds: roundedSeconds, preferredTimescale: start.timescale)

		self.writerDelegate = WriterDelegate(
			start: start,
			segmentInterval: .init(seconds: 6, preferredTimescale: 1),
			writers: writers
		)
		assetWriter.delegate = writerDelegate

		assetWriter.initialSegmentStartTime = start
		assetWriter.startWriting()
		assetWriter.startSession(atSourceTime: start)

		defer {
			videoInput.markAsFinished()
			assetWriter.endSession(atSourceTime: clock.time)
			assetWriter.cancelWriting()
		}

		var lastPresentationTime: CMTime?

		for await frame in syphonClient.frames {
			let presentationTime = CMTimeConvertScale(frame.time, timescale: 30, method: .default)
			guard presentationTime != lastPresentationTime else {
//								logger.warning("next frame too soon, skipping")
				continue
			}
			lastPresentationTime = presentationTime

			switch assetWriter.status {
			case .unknown:
				continue
			case .cancelled:
				throw CancellationError()
			case .failed:
				throw assetWriter.error ?? HLSAssetWriterError.invalidWriterStatus(assetWriter.status)
			case .completed:
				return
			case .writing:
				break
			@unknown default:
				continue
			}

			guard videoInput.isReadyForMoreMediaData else {
				logger.warning("video input not ready")
				continue
			}

			let size = AVMakeRect(
				aspectRatio: frame.image.extent.size,
				insideRect: CGRect(
					origin: .zero,
					size: CGSize(
						width: quality.resolutions.width,
						height: quality.resolutions.height
					)
				)
			)
			let image = frame.image
				.transformed(by: CGAffineTransform(
					scaleX: size.size.width / frame.image.extent.size.width,
					y: size.size.height / frame.image.extent.size.height
				))

			guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
				logger.error("Pixel buffer asset writer input did not have a pixel buffer pool available; cannot retrieve frame")
				continue
			}

			var maybePixelBuffer: CVPixelBuffer?
			let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &maybePixelBuffer)
			guard let pixelBuffer = maybePixelBuffer, status == kCVReturnSuccess else {
				logger.error("Could not get pixel buffer from asset writer input; dropping frame (status \(status))")
				continue
			}

			context.render(image, to: pixelBuffer)

			let result = pixelBufferAdaptor.append(
				pixelBuffer,
				withPresentationTime: presentationTime
			)
			if !result {
				logger.error("could not append pixel buffer at \(String(describing: presentationTime))")
			}
		}
	}
}
