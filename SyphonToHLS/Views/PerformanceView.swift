import Dependencies
import SwiftUI

struct PerformanceView: View {
	@Dependency(\.configManager) private var configManager
	@Dependency(\.performanceTracker) private var performanceTracker

	var streams: [Stream] {
		VideoQualityLevel.allCases
			.filter { configManager.config.encoder.qualityLevels.contains($0) }
			.map { Stream.video($0) } + [.audio]
	}

	var body: some View {
		Grid {
			ForEach(streams, id: \.self) { stream in
				GridRow {
					Text("\(stream.header.capitalized)")
						.frame(maxWidth: .infinity, alignment: .leading)
						.multilineTextAlignment(.leading)

					let encodeAverage = performanceTracker.average(stream: stream, operation: .encode)
					if !encodeAverage.isNaN {
						Text(encodeAverage.formatted(.percent.precision(.fractionLength(0))))
							.gridCellAnchor(.trailing)
					} else {
						Text("-")
							.foregroundStyle(.gray)
					}

					let uploadAverage = performanceTracker.average(stream: stream, operation: .upload)
					if !uploadAverage.isNaN {
						Text(uploadAverage.formatted(.percent.precision(.fractionLength(0))))
							.gridCellAnchor(.trailing)
					} else {
						Text("-")
							.foregroundStyle(.gray)
					}

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

#Preview {
	PerformanceView()
}
