import AVFoundation
import CoreImage
import Dependencies
import OSLog
import Queue
import VideoToolbox

actor HLSNDIAudioService {
	private let writerDelegate: WriterDelegate?
	private let writers: [HLSWriter]

	@Dependency(\.date) private var date
	@Dependency(\.hostTimeClock) private var clock
	private lazy var assetWriter = AVAssetWriter.hlsWriter(preferredOutputSegmentInterval: preferredOutputSegmentInterval)
	private lazy var audioInput = AVAssetWriterInput.hlsAudioInput()

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
		self.writerDelegate = WriterDelegate(
			writers: writers,
			stream: .audio
		)
	}

	func start() async {
		let currentMediaTime = clock.time
		let currentDate = CMTime(
			seconds: date.now.timeIntervalSince1970,
			preferredTimescale: .init(NDI.timescale)
		)
		let presentationsTimeOffset = currentDate - currentMediaTime

		while !Task.isCancelled {
			do {
				guard assetWriter.status == .unknown else { throw HLSAssetWriterError.invalidWriterStatus(assetWriter.status) }
				
				assetWriter.delegate = writerDelegate
				assetWriter.add(audioInput)

				var start = clock.time
				let preferredOutputSegmentInterval = assetWriter.preferredOutputSegmentInterval.seconds
				let roundedSeconds = (start.seconds / preferredOutputSegmentInterval).rounded(.up) * preferredOutputSegmentInterval
				start = CMTime(seconds: roundedSeconds, preferredTimescale: start.timescale)

				assetWriter.initialSegmentStartTime = start
				assetWriter.startWriting()
				assetWriter.startSession(atSourceTime: start)

				for await frame in player.audioFrames {
					let sampleBuffer: CMSampleBuffer
					do {
						sampleBuffer = try frame.sampleBuffer(presentationsTimeOffset: presentationsTimeOffset)
					} catch {
						logger.error("could not create ndi sample buffer: \(error)")
						continue
					}

					try assetWriter.checkWritable()

					guard audioInput.isReadyForMoreMediaData else {
						logger.warning("audio input not ready")
						continue
					}

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
