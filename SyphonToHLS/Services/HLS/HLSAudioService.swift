import AVFoundation
import OSLog

actor HLSAudioService {
	private let logger = Logger(category: "HLSAudioService")
	private let clock = CMClock.hostTimeClock

	private let assetWriter: AVAssetWriter
	private let captureAudioDataOutputSampleBufferDelegate: CaptureAudioDataOutputSampleBufferDelegate
	private let captureSession = AVCaptureSession()
	private let audioInput: AVAssetWriterInput
	private let writers: [HLSWriter]
	private var writerDelegate: WriterDelegate?

	init(url: URL, audioDevice: AVCaptureDevice, uploader: S3Uploader) {
		self.writers = [
			HLSFileWriter(baseURL: url.appending(component: "audio")),
			HLSS3Writer(uploader: uploader, prefix: "audio"),
		]

		self.assetWriter = AVAssetWriter.hlsWriter()

		let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
			AVFormatIDKey: kAudioFormatMPEG4AAC,

			AVSampleRateKey: 48000,
			AVNumberOfChannelsKey: 1,
			AVEncoderBitRateKey: 80 * 1024,
		])
		audioInput.expectsMediaDataInRealTime = true

		captureAudioDataOutputSampleBufferDelegate = CaptureAudioDataOutputSampleBufferDelegate(
			assetWriter: assetWriter,
			audioInput: audioInput
		)

		captureSession.beginConfiguration()

		// Wrap the audio device in a capture device input.
		let audioDeviceInput = try! AVCaptureDeviceInput(device: audioDevice)

		captureSession.addInput(audioDeviceInput)
		let captureAudioOutput = AVCaptureAudioDataOutput()
		captureAudioOutput.setSampleBufferDelegate(
			captureAudioDataOutputSampleBufferDelegate,
			queue: DispatchQueue(label: "hls_audio")
		)

		captureSession.addOutput(captureAudioOutput)

		captureSession.commitConfiguration()

		assetWriter.add(audioInput)

		self.audioInput = audioInput
	}

	func start() async throws {
		guard assetWriter.status == .unknown else { throw HLSAssetWriterError.invalidWriterStatus(assetWriter.status) }

		captureSession.startRunning()
		defer { captureSession.stopRunning() }

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
			audioInput.markAsFinished()
			assetWriter.endSession(atSourceTime: clock.time)
			assetWriter.cancelWriting()
		}

		for try await _ in captureAudioDataOutputSampleBufferDelegate.stream {}
	}

	final class CaptureAudioDataOutputSampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
		private let logger = Logger(category: "HLSAudioService")

		private let continuation: AsyncThrowingStream<Void, Error>.Continuation
		let stream: AsyncThrowingStream<Void, Error>

		private let assetWriter: AVAssetWriter
		private let audioInput: AVAssetWriterInput

		init(assetWriter: AVAssetWriter, audioInput: AVAssetWriterInput) {
			(stream, continuation) = AsyncThrowingStream.makeStream()

			self.assetWriter = assetWriter
			self.audioInput = audioInput

			super.init()
		}

		func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
			switch assetWriter.status {
			case .unknown:
				return
			case .cancelled:
				continuation.finish(throwing: CancellationError())
			case .failed:
				continuation.finish(throwing: assetWriter.error ?? HLSAssetWriterError.invalidWriterStatus(assetWriter.status))
			case .completed:
				continuation.finish()
			case .writing:
				break
			@unknown default:
				return
			}

			guard audioInput.isReadyForMoreMediaData else {
				logger.warning("audio input not ready")
				return
			}

			audioInput.append(sampleBuffer)
		}
	}
}
