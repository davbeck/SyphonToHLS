import AVFoundation
import Dependencies
import SFSafeSymbols
import SwiftUI

struct ContentMenuView: View {
	private let session = ProfileSession.liveValue

	var body: some View {
		VStack {
			Section {
				SessionVideoSourcePicker()

				SessionAudioSourcePicker()
				
				SessionMonitorSourcePicker()
			}
			
			Section {
				SettingsLink()
				
				SessionStartStopButton()
			}
//			Divider()
//
//			HStack {
//				SettingsLink()
//				
//				Button("Quit") {
//					NSApplication.shared.terminate(nil)
//				}
//				
//				Spacer()
//				
//				SessionStartStopButton()
//			}
		}
		.padding()
	}
}
