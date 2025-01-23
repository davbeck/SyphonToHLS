import AVFoundation
import CoreImage
import Dependencies
import OSLog
import Queue
import VideoToolbox

actor HLSNDIAudioService {
	var writerDelegate: WriterDelegate?
	private let writers: [HLSWriter]

	@Dependency(\.hostTimeClock) private var clock
	private lazy var assetWriter = AVAssetWriter.hlsWriter(preferredOutputSegmentInterval: preferredOutputSegmentInterval)
	private lazy var audioInput = AVAssetWriterInput.hlsAudioInput()

	private let context = CIContext()

	private let logger = Logger(category: "HLSService")

	let preferredOutputSegmentInterval: Double
	let player: NDIPlayer

	init(
		preferredOutputSegmentInterval: Double,
		player: NDIPlayer,
		url: URL,
		uploader: S3Uploader
	) {
		self.preferredOutputSegmentInterval = preferredOutputSegmentInterval
		self.player = player

		self.writers = [
			HLSFileWriter(baseURL: url.appending(component: "audio")),
			HLSS3Writer(uploader: uploader, stream: .audio),
		]
	}

	func start() async {
		while !Task.isCancelled {
			do {
				guard assetWriter.status == .unknown else { throw HLSAssetWriterError.invalidWriterStatus(assetWriter.status) }

				var start = clock.time
				let preferredOutputSegmentInterval = assetWriter.preferredOutputSegmentInterval.seconds
				let roundedSeconds = (start.seconds / preferredOutputSegmentInterval).rounded(.up) * preferredOutputSegmentInterval
				start = CMTime(seconds: roundedSeconds, preferredTimescale: start.timescale)

				self.writerDelegate = WriterDelegate(
					writers: writers,
					stream: .audio
				)
				assetWriter.delegate = writerDelegate

				assetWriter.add(audioInput)

				assetWriter.initialSegmentStartTime = start
				assetWriter.startWriting()
				assetWriter.startSession(atSourceTime: start)

				for await frame in player.audioFrames {
					let presentationTime = clock.convert(frame.timestamp)

					try assetWriter.checkWritable()

					guard audioInput.isReadyForMoreMediaData else {
						logger.warning("audio input not ready")
						continue
					}

					guard let sampleBuffer = frame.sampleBuffer else {
						logger.error("could not create ndi sample buffer")
						continue
					}
					CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, newValue: presentationTime)

					audioInput.append(sampleBuffer)
				}

				audioInput.markAsFinished()
				assetWriter.endSession(atSourceTime: clock.time)
				assetWriter.finishWriting(completionHandler: {})
			} catch {
				logger.error("audio writing failed: \(error)")

				assetWriter = AVAssetWriter.hlsWriter(preferredOutputSegmentInterval: preferredOutputSegmentInterval)
				audioInput = AVAssetWriterInput.hlsAudioInput()
			}
		}
	}
}
