import AVFoundation
import CoreImage
import OSLog
import VideoToolbox

private let url = URL.moviesDirectory.appendingPathComponent("Livestream")

private let queue = DispatchQueue(label: "hls")

actor HLSService {
	enum Error: Swift.Error {
		case notStarted
		case invalidWriterStatus(AVAssetWriter.Status)
	}

	let writerDelegate: WriterDelegate
	let captureAudioDataOutputSampleBufferDelegate: CaptureAudioDataOutputSampleBufferDelegate

	private let clock = CMClock.hostTimeClock
	private let assetWriter: AVAssetWriter
	private let videoInput: AVAssetWriterInput
	private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
	private let captureSession = AVCaptureSession()
	private let audioInput: AVAssetWriterInput

	private let context = CIContext()

	private let logger = Logger(
		subsystem: Bundle(for: HLSService.self).bundleIdentifier ?? "",
		category: "HLSService"
	)

	var recordingStartTime: CFTimeInterval?

	private let delegateTask: Task<Void, Never>
	private let audioCaptureTask: Task<Void, Never>

	init() {
		let (segmentStream, segmentContinuation) = AsyncStream.makeStream(of: Segment.self)
		writerDelegate = .init(continuation: segmentContinuation)

		self.assetWriter = AVAssetWriter(contentType: .mpeg4Movie)

		assetWriter.shouldOptimizeForNetworkUse = true
		assetWriter.outputFileTypeProfile = .mpeg4AppleHLS
		assetWriter.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 1)
		assetWriter.delegate = writerDelegate

		// Video

		self.videoInput = AVAssetWriterInput(
			mediaType: .video,
			outputSettings: [
				AVVideoCodecKey: AVVideoCodecType.h264,
				AVVideoWidthKey: 1920,
				AVVideoHeightKey: 1080,

//				AVVideoCompressionPropertiesKey: [
//					kVTCompressionPropertyKey_AverageBitRate: 6_000_000,
//					kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_4_1,
//				],
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
			struct Record {
				var index: Int
				var duration: CMTime

				var name: String {
					"segment-\(index).m4s"
				}
			}
			var lastIndex = 0
			var records: [Record] = []

			for await segment in segmentStream {
				do {
					switch segment.type {
					case .initialization:
						try segment.data.write(
							to: url.appendingPathComponent("initialization.mp4"),
							options: .atomic
						)
					case .separable:
						guard let trackReport = segment.report?.trackReports.first else { continue }

						lastIndex += 1

						let record = Record(
							index: lastIndex,
							duration: trackReport.duration
						)

						try segment.data.write(
							to: url.appendingPathComponent(record.name),
							options: .atomic
						)

						records.append(record)

						let segmentTemplate = records
							.map { record in
								"""
								#EXTINF:\(record.duration.seconds),
								\(record.name)
								"""
							}
							.joined(separator: "\n")

						let startSequence = records.first?.index ?? 1

						let template = """
						#EXTM3U
						#EXT-X-TARGETDURATION:10
						#EXT-X-VERSION:9
						#EXT-X-MEDIA-SEQUENCE:\(startSequence)
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

		// Audio

		audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
			AVFormatIDKey: kAudioFormatMPEG4AAC,

			AVSampleRateKey: 48000,
			AVNumberOfChannelsKey: 1,
			AVEncoderBitRateKey: 160_000,
		])
		audioInput.expectsMediaDataInRealTime = true

		let (audioCaptureStream, audioCaptureContinuation) = AsyncStream.makeStream(of: CMSampleBuffer.self)
		captureAudioDataOutputSampleBufferDelegate = .init(continuation: audioCaptureContinuation)

		captureSession.beginConfiguration()

		let audioDevice = AVCaptureDevice.default(for: .audio)!
		// Wrap the audio device in a capture device input.
		let audioDeviceInput = try! AVCaptureDeviceInput(device: audioDevice)

		captureSession.addInput(audioDeviceInput)
		let captureAudioOutput = AVCaptureAudioDataOutput()
		captureAudioOutput.setSampleBufferDelegate(captureAudioDataOutputSampleBufferDelegate, queue: queue)

		captureSession.addOutput(captureAudioOutput)

		captureSession.commitConfiguration()

		assetWriter.add(audioInput)

		audioCaptureTask = Task { [assetWriter, audioInput, logger] in
			for await sampleBuffer in audioCaptureStream {
				guard assetWriter.status == .writing else {
					logger.warning("AVAssetWriter is not writing")
					continue
				}
				
				guard audioInput.isReadyForMoreMediaData else {
					logger.warning("audio input not ready")
					continue
				}
				
				audioInput.append(sampleBuffer)
			}
		}
	}

	deinit {
		captureSession.stopRunning()
		videoInput.markAsFinished()
		assetWriter.finishWriting {}

		delegateTask.cancel()
		audioCaptureTask.cancel()
	}

	func start() {
		recordingStartTime = CACurrentMediaTime()

		captureSession.startRunning()

		assetWriter.initialSegmentStartTime = clock.time
		assetWriter.startWriting()
		assetWriter.startSession(atSourceTime: clock.time)
	}

	func stop() async {
		recordingStartTime = nil

		captureSession.stopRunning()

		videoInput.markAsFinished()
		await assetWriter.finishWriting()
	}

	private var lastPresentationTime: CMTime?

	func writeFrame(forTexture texture: MTLTexture) throws {
		guard let recordingStartTime else {
			throw Error.notStarted
		}

		let presentationTime = clock.time
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
			logger.warning("video input not ready")
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

		let result = pixelBufferAdaptor.append(
			pixelBuffer,
			withPresentationTime: presentationTime
		)
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

	final class CaptureAudioDataOutputSampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
		let continuation: AsyncStream<CMSampleBuffer>.Continuation

		init(continuation: AsyncStream<CMSampleBuffer>.Continuation) {
			self.continuation = continuation
		}

		func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
			continuation.yield(sampleBuffer)
		}
	}
}

