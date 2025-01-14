import CoreImage
import SwiftUI

struct SyphonPreviewView: View {
	let client: SyphonCoreImageClient

	@State private var image: CIImage?

	var body: some View {
		MetalView(
			device: client.device,
			image: image
		)
		.task {
			for await frame in client.frames {
				self.image = frame.image
			}
		}
	}
}

// #Preview {
//    SyphonPreviewView()
// }
