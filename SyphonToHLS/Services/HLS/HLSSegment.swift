import AVFoundation
import Foundation

struct HLSSegment {
	var index: Int
	var data: Data
	var type: AVAssetSegmentType
	var report: AVAssetSegmentReport?

	var start: CMTime {
		self.report?.start ?? CMTime.zero
	}

	var duration: CMTime {
		guard let trackReport = self.report?.trackReports.first else { return CMTime.zero }

		return trackReport.duration
	}
}

extension AVAssetSegmentReport {
	var start: CMTime? {
		self.trackReports.map(\.earliestPresentationTimeStamp).min()
	}

	var duration: CMTime? {
		self.trackReports.map(\.duration).max()
	}

	var end: CMTime? {
		self.trackReports.map { report in
			report.earliestPresentationTimeStamp + report.duration
		}
		.max()
	}
}
