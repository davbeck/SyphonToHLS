import AVFoundation
import Cocoa
import Metal
import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
	typealias NSViewType = MTKView

	var device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()
	var texture: MTLTexture?

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	func makeNSView(context: NSViewRepresentableContext<MetalView>) -> MTKView {
		let view = MTKView()
		view.delegate = context.coordinator
		//		view.backgroundColor = context.environment.colorScheme == .dark ? UIColor.white : UIColor.white
		//		view.isOpaque = true
		view.enableSetNeedsDisplay = true

		view.framebufferOnly = false
		view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
		view.drawableSize = view.frame.size
		view.enableSetNeedsDisplay = true

		return view
	}

	func updateNSView(_ view: MTKView, context: NSViewRepresentableContext<MetalView>) {
		view.device = device

		context.coordinator.parent = self
		context.coordinator.mtkView = view
		
		view.isPaused = texture == nil
	}

	class Coordinator: NSObject, MTKViewDelegate {
		var parent: MetalView {
			didSet {
				if oldValue.device !== parent.device {
					metalCommandQueue = parent.device?.makeCommandQueue()
					ciContext = parent.device.flatMap { CIContext(mtlDevice: $0) }
				}
			}
		}

		var ciContext: CIContext?

		var metalCommandQueue: MTLCommandQueue?

		var mtkView: MTKView? {
			didSet {
				oldValue?.delegate = nil
				mtkView?.delegate = self
			}
		}

		init(_ parent: MetalView) {
			self.parent = parent

			metalCommandQueue = parent.device?.makeCommandQueue()
			ciContext = parent.device.flatMap { CIContext(mtlDevice: $0) }

			super.init()
		}

		func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

		func draw(in view: MTKView) {
			guard
				let texture = parent.texture,
				let metalCommandQueue,
				let ciContext,
				let drawable = view.currentDrawable,
				let inputImage = CIImage(mtlTexture: texture),
				let commandBuffer = metalCommandQueue.makeCommandBuffer()
			else {
				return
			}

			var size = view.bounds
			size.size = view.drawableSize
			size = AVMakeRect(aspectRatio: inputImage.extent.size, insideRect: size)
			let filteredImage = inputImage.transformed(by: CGAffineTransform(
				scaleX: size.size.width / inputImage.extent.size.width,
				y: size.size.height / inputImage.extent.size.height
			))
			let x = -size.origin.x
			let y = -size.origin.y

			ciContext.render(
				filteredImage,
				to: drawable.texture,
				commandBuffer: commandBuffer,
				bounds: CGRect(origin: CGPoint(x: x, y: y), size: view.drawableSize),
				colorSpace: CGColorSpaceCreateDeviceRGB()
			)

			commandBuffer.present(drawable)
			commandBuffer.commit()
		}

//		func getNSImage(texture: MTLTexture, context: CIContext) -> NSImage? {
//			let kciOptions = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB(),
//			                  CIContextOption.outputPremultiplied: true,
//			                  CIContextOption.useSoftwareRenderer: false] as! [CIImageOption: Any]
//
//			if let ciImageFromTexture = CIImage(mtlTexture: texture, options: kciOptions) {
//				if let cgImage = context.createCGImage(ciImageFromTexture, from: ciImageFromTexture.extent) {
//					let nsImage = NSImage(cgImage: cgImage, size: .init(width: cgImage.width, height: cgImage.height))
//					return nsImage
//				} else {
//					return nil
//				}
//			} else {
//				return nil
//			}
//		}
	}
}
