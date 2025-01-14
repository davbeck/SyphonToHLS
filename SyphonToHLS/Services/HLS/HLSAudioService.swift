import AVFoundation
import OSLog

extension AVAssetWriterInput {
	static func hlsInput() -> AVAssetWriterInput {
		let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
			AVFormatIDKey: kAudioFormatMPEG4AAC,

			AVSampleRateKey: 48000,
			AVNumberOfChannelsKey: 1,
			AVEncoderBitRateKey: 80 * 1024,
		])
		input.expectsMediaDataInRealTime = true
		return input
	}
}

final class HLSAudioService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
	private let logger = Logger(category: "HLSAudioService")
	private let clock = CMClock.hostTimeClock

	private let queue = DispatchQueue(label: "HLSAudioService")

	private var assetWriter = AVAssetWriter.hlsWriter()
	private let captureAudioOutput = AVCaptureAudioDataOutput()
	private var audioInput: AVAssetWriterInput = .hlsInput()
	private let captureSession: AVCaptureSession
	private let writers: [HLSWriter]
	private var writerDelegate: WriterDelegate?

	private var isRunning: Bool = false

	init(url: URL, audioDevice: AVCaptureDevice, captureSession: AVCaptureSession, uploader: S3Uploader) {
		self.captureSession = captureSession

		self.writers = [
			HLSFileWriter(baseURL: url.appending(component: "audio")),
			HLSS3Writer(uploader: uploader, stream: .audio),
		]

		let audioInput = AVAssetWriterInput.hlsInput()
		audioInput.expectsMediaDataInRealTime = true
	}

	private func setupAssetWriter() {
		dispatchPrecondition(condition: .onQueue(queue))

		assetWriter.add(audioInput)

		var start = clock.time
		let roundedSeconds = (start.seconds / 6).rounded(.up) * 6
		start = CMTime(seconds: roundedSeconds, preferredTimescale: start.timescale)

		self.writerDelegate = WriterDelegate(
			start: start,
			segmentInterval: assetWriter.preferredOutputSegmentInterval,
			writers: writers,
			stream: .audio
		)
		assetWriter.delegate = writerDelegate

		assetWriter.initialSegmentStartTime = start
		assetWriter.startWriting()
		assetWriter.startSession(atSourceTime: start)
	}

	private func cleanupAssetWriter() {
		dispatchPrecondition(condition: .onQueue(queue))

		audioInput.markAsFinished()
		if assetWriter.status == .writing {
			assetWriter.endSession(atSourceTime: clock.time)
		 assetWriter.cancelWriting()
		}
	}

	func start() {
		queue.async { [self] in
			isRunning = true

			captureSession.beginConfiguration()
			captureAudioOutput.setSampleBufferDelegate(
				self,
				queue: DispatchQueue(label: "hls_audio")
			)
			captureSession.addOutput(captureAudioOutput)
			captureSession.commitConfiguration()

			setupAssetWriter()
		}
	}

	private func restart() {
		dispatchPrecondition(condition: .onQueue(queue))

		guard isRunning else { return }

		cleanupAssetWriter()

		self.assetWriter = AVAssetWriter.hlsWriter()
		self.audioInput = AVAssetWriterInput.hlsInput()

		setupAssetWriter()
	}

	func stop() {
		queue.async { [self] in
			isRunning = false

			captureSession.beginConfiguration()
			captureSession.removeOutput(captureAudioOutput)
			captureSession.commitConfiguration()

			cleanupAssetWriter()
		}
	}

	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		// AVCaptureAudioDataOutput will skip outputs if the callback queue is not free, so simulate being free by immediately switching queue's
		queue.async { [self] in
			switch assetWriter.status {
			case .unknown:
				logger.warning("asset writer unknown status: \(self.assetWriter.status.rawValue)")
				self.restart()
			case .cancelled:
				logger.warning("asset writer cancelled")
				self.restart()
			case .failed:
				if let error = assetWriter.error {
					logger.error("asset writer failed: \(error)")
				} else {
					logger.error("asset writer failed")
				}

				self.restart()
			case .completed:
				logger.warning("asset writer completed")
				self.restart()
			case .writing:
				break
			@unknown default:
				logger.warning("asset writer unknown status: \(self.assetWriter.status.rawValue)")
				self.restart()
			}

			audioInput.append(sampleBuffer)
		}
	}
}
