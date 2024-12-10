import AVFoundation
import CoreImage
import OSLog
import Queue
import VideoToolbox

private let queue = DispatchQueue(label: "hls")

actor HLSService {
	enum Error: Swift.Error {
		case notStarted
		case invalidWriterStatus(AVAssetWriter.Status)
	}

	let syphonClient: SyphonCoreImageClient?

	let writerDelegate: WriterDelegate
	let captureAudioDataOutputSampleBufferDelegate = CaptureAudioDataOutputSampleBufferDelegate()

	private let clock = CMClock.hostTimeClock
	private let assetWriter: AVAssetWriter
	private let videoInput: AVAssetWriterInput?
	private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
	private let captureSession = AVCaptureSession()
	private let audioInput: AVAssetWriterInput?

	private let start: Date

	private let context = CIContext()

	private let logger = Logger(category: "HLSService")

	private let prefix: String

	init(url: URL, syphonClient: SyphonCoreImageClient?, audioDevice: AVCaptureDevice?) {
		self.start = .now

		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
		prefix = dateFormatter.string(from: start)

		self.writerDelegate = WriterDelegate(writers: [
			HLSFileWriter(baseURL: url, prefix: prefix),
			HLSS3Writer(prefix: prefix),
		])

		self.syphonClient = syphonClient

		self.assetWriter = AVAssetWriter(contentType: .mpeg4Movie)

		assetWriter.shouldOptimizeForNetworkUse = true
		assetWriter.outputFileTypeProfile = .mpeg4AppleHLS
		assetWriter.preferredOutputSegmentInterval = CMTime(seconds: 6, preferredTimescale: 1)
		assetWriter.delegate = writerDelegate

		// Video
		if syphonClient != nil {
			let videoInput = AVAssetWriterInput(
				mediaType: .video,
				outputSettings: [
					AVVideoCodecKey: AVVideoCodecType.h264,
					AVVideoWidthKey: 1920,
					AVVideoHeightKey: 1080,

					AVVideoCompressionPropertiesKey: [
						kVTCompressionPropertyKey_AverageBitRate: 6 * 1024 * 1024,
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
					kCVPixelBufferWidthKey as String: 1920,
					kCVPixelBufferHeightKey as String: 1080,
					kCVPixelBufferMetalCompatibilityKey as String: true,
				]
			)

			self.videoInput = videoInput
		} else {
			self.videoInput = nil
			self.pixelBufferAdaptor = nil
		}

		// Audio
		if let audioDevice {
			let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
				AVFormatIDKey: kAudioFormatMPEG4AAC,

				AVSampleRateKey: 48000,
				AVNumberOfChannelsKey: 1,
				AVEncoderBitRateKey: 80 * 1024,
			])
			audioInput.expectsMediaDataInRealTime = true

			captureSession.beginConfiguration()

			// Wrap the audio device in a capture device input.
			let audioDeviceInput = try! AVCaptureDeviceInput(device: audioDevice)

			captureSession.addInput(audioDeviceInput)
			let captureAudioOutput = AVCaptureAudioDataOutput()
			captureAudioOutput.setSampleBufferDelegate(captureAudioDataOutputSampleBufferDelegate, queue: queue)

			captureSession.addOutput(captureAudioOutput)

			captureSession.commitConfiguration()

			assetWriter.add(audioInput)

			self.audioInput = audioInput
		} else {
			self.audioInput = nil
		}
	}

	func start() async throws {
		captureSession.startRunning()

		assetWriter.initialSegmentStartTime = clock.time
		assetWriter.startWriting()
		assetWriter.startSession(atSourceTime: clock.time)

		defer {
			captureSession.stopRunning()

			audioInput?.markAsFinished()
			videoInput?.markAsFinished()
			assetWriter.endSession(atSourceTime: clock.time)
			assetWriter.cancelWriting()
		}

		try await withThrowingTaskGroup(of: Void.self) { [assetWriter, audioInput, logger, writerDelegate, captureAudioDataOutputSampleBufferDelegate] group in
			if let audioInput {
				group.addTask {
					for await sampleBuffer in captureAudioDataOutputSampleBufferDelegate.stream {
						switch assetWriter.status {
						case .unknown:
							continue
						case .cancelled:
							throw CancellationError()
						case .failed:
							throw assetWriter.error ?? Error.invalidWriterStatus(assetWriter.status)
						case .completed:
							return
						case .writing:
							break
						@unknown default:
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

			if let videoInput, let syphonClient, let pixelBufferAdaptor {
				group.addTask { [syphonClient, context] in
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
							throw assetWriter.error ?? Error.invalidWriterStatus(assetWriter.status)
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
							insideRect: CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080))
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

			try await group.waitForAll()
		}
	}

	final class WriterDelegate: NSObject, AVAssetWriterDelegate, Sendable {
		let outputs: [(writer: HLSWriter, queue: AsyncQueue)]

		init(writers: [HLSWriter]) {
			self.outputs = writers.map { ($0, .init()) }

			super.init()
		}

		func assetWriter(
			_ writer: AVAssetWriter,
			didOutputSegmentData segmentData: Data,
			segmentType: AVAssetSegmentType,
			segmentReport: AVAssetSegmentReport?
		) {
			for (writer, queue) in self.outputs {
				queue.addOperation {
					try await writer.write(.init(
						data: segmentData,
						type: segmentType,
						report: segmentReport
					))
				}
			}
		}
	}

	final class CaptureAudioDataOutputSampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
		private let continuation: AsyncStream<CMSampleBuffer>.Continuation
		let stream: AsyncStream<CMSampleBuffer>

		override init() {
			(stream, continuation) = AsyncStream.makeStream()

			super.init()
		}

		func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
			continuation.yield(sampleBuffer)
		}
	}
}
