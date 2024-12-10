import AVFoundation
import Foundation

struct HLSSegment {
	var data: Data
	var type: AVAssetSegmentType
	var report: AVAssetSegmentReport?
	
	var start: CMTime {
		guard let trackReport = self.report?.trackReports.first else { return CMTime.zero }
		
		return trackReport.earliestPresentationTimeStamp
	}

	var duration: CMTime {
		guard let trackReport = self.report?.trackReports.first else { return CMTime.zero }

		return trackReport.duration
	}
}
