import AVFoundation
import CoreImage
import OSLog

private let url = URL(fileURLWithPath: "/Users/davbeck/Movies/Livestream")

private let queue = DispatchQueue(label: "hls")

actor HLSService {
	enum Error: Swift.Error {
		case notStarted
		case invalidWriterStatus(AVAssetWriter.Status)
	}

	let writerDelegate: WriterDelegate

	private let assetWriter: AVAssetWriter
	private let videoInput: AVAssetWriterInput
	private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

	private let context = CIContext()

	private let logger = Logger(
		subsystem: Bundle(for: HLSService.self).bundleIdentifier ?? "",
		category: "HLSService"
	)

	var recordingStartTime: CFTimeInterval?

	private let delegateTask: Task<Void, Never>

	init() {
		let (segmentStream, segmentContinuation) = AsyncStream.makeStream(of: Segment.self)
		writerDelegate = .init(continuation: segmentContinuation)

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

		delegateTask = Task { [logger] in
			var segmentCount = 0
			for await segment in segmentStream {
				do {
					switch segment.type {
					case .initialization:
						try segment.data.write(
							to: url.appendingPathComponent("initialization.mp4"),
							options: .atomic
						)
					case .separable:
						try segment.data.write(
							to: url.appendingPathComponent("segment-\(segmentCount).m4s"),
							options: .atomic
						)

						segmentCount += 1

						let segmentTemplate = (0 ..< segmentCount)
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
					@unknown default:
						logger.error("@unknown segment type \(segment.type.rawValue)")
					}
				} catch {
					logger.error("failed to write segment data: \(error)")
				}
			}
		}
	}
	
	deinit {
		delegateTask.cancel()
	}

	func start() {
		recordingStartTime = CACurrentMediaTime()

		assetWriter.initialSegmentStartTime = .zero
		assetWriter.startWriting()
		assetWriter.startSession(atSourceTime: .zero)
	}

	func stop() async {
		recordingStartTime = nil

		videoInput.markAsFinished()
		await assetWriter.finishWriting()
	}

	private var lastPresentationTime: CMTime?

	func writeFrame(forTexture texture: MTLTexture) throws {
		guard let recordingStartTime else {
			throw Error.notStarted
		}

		let frameTime = CACurrentMediaTime() - recordingStartTime
		let presentationTime = CMTimeMakeWithSeconds(frameTime, preferredTimescale: 240)
		guard presentationTime != lastPresentationTime else {
			logger.warning("next frame too soon, skipping")
			return
		}
		lastPresentationTime = presentationTime

		guard assetWriter.status == .writing else {
			if let error = assetWriter.error {
				throw error
			} else {
				throw Error.invalidWriterStatus(assetWriter.status)
			}
		}

		guard videoInput.isReadyForMoreMediaData else {
			logger.warning("input not ready")
			return
		}

		guard let image = CIImage(mtlTexture: texture) else {
			logger.error("invalid image")
			return
		}

		guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
			logger.error("Pixel buffer asset writer input did not have a pixel buffer pool available; cannot retrieve frame")
			return
		}

		var maybePixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &maybePixelBuffer)
		guard let pixelBuffer = maybePixelBuffer, status == kCVReturnSuccess else {
			logger.error("Could not get pixel buffer from asset writer input; dropping frame (status \(status))")
			return
		}

		context.render(image, to: pixelBuffer)

		let result = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
		if !result {
			logger.error("could not append pixel buffer at \(String(describing: presentationTime))")
		}
	}

	struct Segment {
		var data: Data
		var type: AVAssetSegmentType
		var report: AVAssetSegmentReport?
	}

	final class WriterDelegate: NSObject, AVAssetWriterDelegate, Sendable {
		let continuation: AsyncStream<Segment>.Continuation

		init(continuation: AsyncStream<Segment>.Continuation) {
			self.continuation = continuation
		}

		func assetWriter(
			_ writer: AVAssetWriter,
			didOutputSegmentData segmentData: Data,
			segmentType: AVAssetSegmentType,
			segmentReport: AVAssetSegmentReport?
		) {
			continuation.yield(
				.init(
					data: segmentData,
					type: segmentType,
					report: segmentReport
				)
			)
		}
	}
}
