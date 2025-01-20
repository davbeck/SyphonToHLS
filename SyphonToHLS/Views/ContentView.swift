import AVFoundation
import Dependencies
import SwiftUI
import Syphon

struct ContentView: View {
	@Dependency(\.configManager) private var configManager

	private let session = ProfileSession.liveValue

	var body: some View {
		VStack {
			SessionVideoSourcePicker()

			SessionAudioSourcePicker()

			SessionMonitorSourcePicker()

			if let frameSource = session.frameSource {
				FrameSourcePreviewView(frameSource: frameSource)
			} else {
				Rectangle().fill(Color.black)
			}
			
			PerformanceView()

			HStack {
				Spacer()

				SessionStartStopButton()
			}
		}
		.padding()
		.task {
			guard let ndiName = configManager.config.videoSource?.ndiName else { return }
			
			let clock = CMClock.hostTimeClock
			
			let player = NDIPlayer(name: ndiName)
			
			let url = URL.moviesDirectory
				.appending(component: "NDIAudio")
				.appending(component: String(describing: Int(Date.now.timeIntervalSince1970)))
				.appendingPathExtension(for: .mpeg4Audio)
			print(url.path(percentEncoded: false))
			let assetWriter = try! AVAssetWriter(url: url, fileType: .m4a)
			assetWriter.shouldOptimizeForNetworkUse = true
			
			let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
				AVFormatIDKey: kAudioFormatMPEG4AAC,

				AVSampleRateKey: 48000,
				AVNumberOfChannelsKey: 1,
				AVEncoderBitRateKey: 80 * 1024,
			])
			input.expectsMediaDataInRealTime = true
			assetWriter.add(input)
			
			assetWriter.startWriting()
			assetWriter.startSession(atSourceTime: clock.time)
			
			let start = Date.now
			for await frame in player.audioFrames {
				guard let sampleBuffer = frame.sampleBuffer else {
					print("missing sampleBuffer")
					continue
				}
				
				let date = Date.now
				let time = clock.time
				let diff: TimeInterval
				if let timestamp = frame.timestamp {
					diff = date.timeIntervalSince(timestamp)
				} else {
					diff = 0
				}
				let presentationTime = time - CMTime(seconds: diff, preferredTimescale: 10_000_000)
				CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, newValue: presentationTime)
				
				input.append(sampleBuffer)
				
				if Date.now.timeIntervalSince(start) > 15 {
					break
				}
			}
			
			input.markAsFinished()
			
			assetWriter.endSession(atSourceTime: clock.time)
			assetWriter.finishWriting {
				print("finished")
			}
//			assetWriter.cancelWriting()
		}
	}
}

#Preview {
	ContentView()
}
