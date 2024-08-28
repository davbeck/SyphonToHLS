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

	let writerDelegate = WriterDelegate()
	let captureAudioDataOutputSampleBufferDelegate = CaptureAudioDataOutputSampleBufferDelegate()

	private let clock = CMClock.hostTimeClock
	private let assetWriter: AVAssetWriter
	private let videoInput: AVAssetWriterInput
	private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
	private let captureSession = AVCaptureSession()
	private let audioInput: AVAssetWriterInput

	let writers: [HLSWriter] = [
		HLSFileWriter(baseURL: url),
		HLSS3Writer(),
	]

	private let context = CIContext()

	private let logger = Logger(
		subsystem: Bundle(for: HLSService.self).bundleIdentifier ?? "",
		category: "HLSService"
	)

	init() {
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

		// Audio

		audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
			AVFormatIDKey: kAudioFormatMPEG4AAC,

			AVSampleRateKey: 48000,
			AVNumberOfChannelsKey: 1,
			AVEncoderBitRateKey: 160_000,
		])
		audioInput.expectsMediaDataInRealTime = true

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
	}

	deinit {
		captureSession.stopRunning()
		videoInput.markAsFinished()
		assetWriter.finishWriting {}
	}

	func start() async {
		captureSession.startRunning()

		assetWriter.initialSegmentStartTime = clock.time
		assetWriter.startWriting()
		assetWriter.startSession(atSourceTime: clock.time)

		let writerOutputs = writers.map { writer in
			(
				writer: writer,
				chunks: AsyncStream.makeStream(of: HLSWriterChunk.self, bufferingPolicy: .unbounded)
			)
		}

		await withTaskGroup(of: Void.self) { [assetWriter, audioInput, logger, writerDelegate, captureAudioDataOutputSampleBufferDelegate] group in
			group.addTask {
				for await sampleBuffer in captureAudioDataOutputSampleBufferDelegate.stream {
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

			for output in writerOutputs {
				group.addTask {
					for await chunk in output.chunks.stream {
						do {
							try await output.writer.write(chunk)
						} catch {
							logger.error("failed to write chunk \(chunk.key) to \(String(describing: output.writer)): \(error)")
						}
					}
				}
			}

			group.addTask {
				var lastIndex = 0
				var records: [HLSRecord] = []

				for await segment in writerDelegate.stream {
					switch segment.type {
					case .initialization:
						for output in writerOutputs {
							output.chunks.continuation.yield(.init(data: segment.data, key: "0.mp4", type: .mpeg4Movie))
						}
					case .separable:
						guard let trackReport = segment.report?.trackReports.first else { continue }

						lastIndex += 1

						let record = HLSRecord(
							index: lastIndex,
							duration: trackReport.duration
						)
						records.append(record)

						let template = records.hlsPlaylist()

						for output in writerOutputs {
							output.chunks.continuation.yield(.init(data: segment.data, key: record.name, type: .segmentedVideo))
							output.chunks.continuation.yield(.init(data: Data(template.utf8), key: "live.m3u8", type: .m3uPlaylist))
						}
					@unknown default:
						logger.error("@unknown segment type \(segment.type.rawValue)")
					}
				}
			}

			await group.waitForAll()
		}

		// cleanup
		captureSession.stopRunning()

		videoInput.markAsFinished()
		await assetWriter.finishWriting()
	}

	private var lastPresentationTime: CMTime?

	func writeFrame(forTexture texture: MTLTexture) throws {
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
		private let continuation: AsyncStream<Segment>.Continuation
		let stream: AsyncStream<Segment>

		override init() {
			(stream, continuation) = AsyncStream.makeStream()

			super.init()
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