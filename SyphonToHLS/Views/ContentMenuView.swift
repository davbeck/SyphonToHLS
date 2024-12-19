import AVFoundation
import Dependencies
import SFSafeSymbols
import SwiftUI

struct ContentMenuView: View {
	@Dependency(\.performanceTracker) private var performanceTracker

	@State private var session = ProfileSession.shared
	@State private var appStorage = AppStorage.shared

	var body: some View {
		VStack {
			Section {
				SessionVideoSourcePicker()

				SessionAudioSourcePicker()
				
				SessionMonitorSourcePicker()

				stats
			}
			
			Divider()

			HStack {
				SettingsLink()
				
				Button("Quit") {
					NSApplication.shared.terminate(nil)
				}
				
				Spacer()
				
				SessionStartStopButton()
			}
		}
		.padding()
	}

	private var stats: some View {
		ForEach(Stream.allCases, id: \.self) { stream in
			if !performanceTracker.average(stream: stream).isNaN {
				HStack {
					Text("\(stream.header.capitalized)")
					Spacer()
					
					Text(performanceTracker.average(stream: stream).formatted(.percent.precision(.fractionLength(0))))
					
					icon(stream)
				}
			}
		}
	}

	private func icon(_ stream: Stream) -> some View {
		if performanceTracker.average(stream: stream) > 1 {
			Image(systemSymbol: .exclamationmarkOctagonFill)
				.foregroundStyle(.red)
		} else if performanceTracker.max(stream: stream) > 1 {
			Image(systemSymbol: .exclamationmarkTriangleFill)
				.foregroundStyle(.yellow)
		} else {
			Image(systemSymbol: .checkmarkCircleFill)
				.foregroundStyle(.green)
		}
	}
}
