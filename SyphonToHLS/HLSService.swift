import AVFoundation
import CoreImage

private let url = URL(fileURLWithPath: "/Users/davbeck/Movies/Livestream")

private let queue = DispatchQueue(label: "hls")

actor HLSService {
	let writerDelegate = WriterDelegate()

	private let assetWriter: AVAssetWriter
	private let videoInput: AVAssetWriterInput
	private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

	private let context = CIContext()

	var recordingStartTime: CFTimeInterval?

	init() {
//		try? FileManager.default.removeItem(at: url)
//		self.assetWriter = try! AVAssetWriter(outputURL: url.appendingPathComponent("livestream.m4v"), fileType: .m4v)

		self.assetWriter = AVAssetWriter(contentType: .mpeg4Movie)

		assetWriter.shouldOptimizeForNetworkUse = true
		assetWriter.outputFileTypeProfile = .mpeg4AppleHLS
		assetWriter.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 1)
		assetWriter.delegate = writerDelegate

		self.videoInput = AVAssetWriterInput(
			mediaType: .video,
			outputSettings: [
				AVVideoCodecKey: AVVideoCodecType.h264,
				AVVideoWidthKey: 1920,
				AVVideoHeightKey: 1080,
			]
		)
		videoInput.expectsMediaDataInRealTime = true
		assetWriter.add(videoInput)

		self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
			assetWriterInput: videoInput,
			sourcePixelBufferAttributes: [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, // bgra8Unorm
				kCVPixelBufferWidthKey as String: 1920,
				kCVPixelBufferHeightKey as String: 1080,
				kCVPixelBufferMetalCompatibilityKey as String: true,
			]
		)
	}

	func start() {
		recordingStartTime = CACurrentMediaTime()

		assetWriter.initialSegmentStartTime = .zero
		assetWriter.startWriting()
		assetWriter.startSession(atSourceTime: .zero)
	}

	func stop() async {
		videoInput.markAsFinished()
		await assetWriter.finishWriting()
	}

	private var lastPresentationTime: CMTime?

	func writeFrame(forTexture texture: MTLTexture) {
		guard let recordingStartTime else {
			print("not started")
			return
		}
		let frameTime = CACurrentMediaTime() - recordingStartTime
		let presentationTime = CMTimeMakeWithSeconds(frameTime, preferredTimescale: 240)
		guard presentationTime != lastPresentationTime else {
			print("next frame too soon, skipping")
			return
		}
		lastPresentationTime = presentationTime

		guard assetWriter.status == .writing else {
			print("invalid status \(assetWriter.status): \(assetWriter.error)")
			return
		}

		guard videoInput.isReadyForMoreMediaData else {
			print("input not ready")
			return
		}

		guard var image = CIImage(mtlTexture: texture) else {
			print("invalid image")
			return
		}
//		image = image
//			.transformed(by: CGAffineTransformMakeScale(1, -1))
//			.transformed(by: CGAffineTransformMakeTranslation(0, image.extent.size.height))

		guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
			print("Pixel buffer asset writer input did not have a pixel buffer pool available; cannot retrieve frame")
			return
		}

		var maybePixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &maybePixelBuffer)
		if status != kCVReturnSuccess {
			print("Could not get pixel buffer from asset writer input; dropping frame status: \(status)")
			return
		}

		guard let pixelBuffer = maybePixelBuffer else { return }

//		CVPixelBufferLockBaseAddress(pixelBuffer, [])
//		let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer)!

		// Use the bytes per row value from the pixel buffer since its stride may be rounded up to be 16-byte aligned
//		let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
//		let region = MTLRegionMake2D(0, 0, texture.width, texture.height)

		context.render(image, to: pixelBuffer)
		print("texture pixelFormat: \(texture.pixelFormat.rawValue) bytesPerRow: \(texture.bufferBytesPerRow) textureType: \(texture.textureType.rawValue)")
//		texture.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

		let result = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
		if !result {
			print("append fail?!?!")
		}

//		CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
	}

	final class WriterDelegate: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
		var segments: Int = 0

		func assetWriter(
			_ writer: AVAssetWriter,
			didOutputSegmentData segmentData: Data,
			segmentType: AVAssetSegmentType,
			segmentReport: AVAssetSegmentReport?
		) {
//			print("didOutputSegmentData", segmentData, segmentType, segmentReport)

			switch segmentType {
			case .initialization:
				queue.async {
					do {
						try segmentData.write(
							to: url.appendingPathComponent("initialization.mp4"),
							options: .atomic
						)
					} catch {
						print("failed to write initialization data: \(error)")
					}
				}
			case .separable:
				guard let trackReports = segmentReport?.trackReports.first else { return }

				let timestamp = trackReports.earliestPresentationTimeStamp
				let duration = trackReports.duration

				let formattedTimestamp = Duration.seconds(timestamp.seconds).formatted()
				print("earliestPresentationTimeStamps", formattedTimestamp)
				queue.async {
					do {
						try segmentData.write(
							to: url.appendingPathComponent("segment-\(self.segments).m4s"),
							options: .atomic
						)

						self.segments += 1

						let segmentTemplate = (0 ..< self.segments)
							.map {
								"""
								#EXTINF:1.0,
								segment-\($0).m4s
								"""
							}
							.joined(separator: "\n")

						let template = """
						#EXTM3U
						#EXT-X-VERSION:9
						#EXT-X-MAP:URI="initialization.mp4"
						\(segmentTemplate)
						"""

						try template.write(
							to: url.appendingPathComponent("live.m3u8"),
							atomically: true,
							encoding: .utf8
						)
					} catch {
						print("failed to write segment data: \(error)")
					}
				}
			@unknown default:
				print("@unknown \(segmentType.rawValue)")
			}
		}
	}
}

extension AVAssetWriter.Status: CustomStringConvertible {
	public var description: String {
		switch self {
		case .unknown:
			"unknown"
		case .writing:
			"writing"
		case .completed:
			"completed"
		case .failed:
			"failed"
		case .cancelled:
			"cancelled"
		@unknown default:
			"@unknown \(rawValue)"
		}
	}
}
