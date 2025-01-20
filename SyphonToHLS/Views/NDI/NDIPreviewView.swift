import SwiftUI

struct FrameSourcePreviewView: View {
	var frameSource: any VideoFrameSource

	@State private var device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()
	@State private var image: CIImage?

	var body: some View {
		MetalView(
			device: device,
			image: image
		)
		.task(id: ObjectIdentifier(frameSource)) {
			for await frame in frameSource.frames {
				self.image = frame.image
			}
		}
	}
}

// #Preview {
//	NDIPreviewView(name: "")
// }
