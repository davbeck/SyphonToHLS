import CoreGraphics
import CoreImage

final class NDIVideoFrame: @unchecked Sendable {
	let receiver: NDIReceiver
	fileprivate var ref: NDIlib_video_frame_v2_t

	init(_ ref: NDIlib_video_frame_v2_t, receiver: NDIReceiver) {
		self.ref = ref
		self.receiver = receiver
	}

	deinit {
		NDIlib_recv_free_video_v2(receiver.pNDI_recv, &ref)
	}

	var resolution: CGSize {
		.init(width: CGFloat(ref.xres), height: CGFloat(ref.yres))
	}

	var timecode: Duration {
		Duration.nanoseconds(ref.timecode * 100)
	}

	var timestamp: Date? {
		Date(ndiTimestamp: ref.timestamp)
	}

	var metadata: String? {
		guard let p_metadata = ref.p_metadata else { return nil }
		return String(cString: p_metadata)
	}

	var pixelBuffer: CVPixelBuffer? {
		// from https://github.com/atelierars/swift-NDI/blob/86f05245faa334b3b9e0835543ce6b020a3a32d0/Sources/NDILib/Recv.swift
		switch ref.FourCC {
		case NDIlib_FourCC_video_type_UYVY:
			var result: CVPixelBuffer?
			return CVPixelBufferCreateWithBytes(
				kCFAllocatorDefault,
				.init(ref.xres),
				.init(ref.yres),
				kCVPixelFormatType_422YpCbCr8,
				ref.p_data,
				.init(ref.line_stride_in_bytes),
				{ obj, mem in obj.map(UnsafeRawPointer.init).map(Unmanaged<NDIVideoFrame>.fromOpaque)?.release() },
				Unmanaged.passRetained(self).toOpaque(),
				.none,
				&result
			) == kCVReturnSuccess ? result : .none
		case NDIlib_FourCC_video_type_UYVA:
			var result: CVPixelBuffer?
			let planeProperties = UnsafeMutablePointer<Int>.allocate(capacity: 6)
			let planeWidth = planeProperties.advanced(by: 0)
			let planeHeight = planeProperties.advanced(by: 2)
			let planeBytesPerRow = planeProperties.advanced(by: 4)
			let planeBaseAddress = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 2)
			defer {
				planeProperties.deallocate()
				planeBaseAddress.deallocate()
			}
			planeWidth[0] = .init(ref.xres)
			planeWidth[1] = .init(ref.xres)
			planeHeight[0] = .init(ref.yres)
			planeHeight[1] = .init(ref.yres)
			planeBytesPerRow[0] = .init(ref.line_stride_in_bytes)
			planeBytesPerRow[1] = .init(ref.line_stride_in_bytes)
			planeBaseAddress[0] = .init(ref.p_data)
			planeBaseAddress[1] = .init(ref.p_data.advanced(by: .init(ref.line_stride_in_bytes * ref.yres)))
			return CVPixelBufferCreateWithPlanarBytes(
				kCFAllocatorDefault,
				.init(ref.xres),
				.init(ref.yres),
				kCVPixelFormatType_422YpCbCr_4A_8BiPlanar,
				ref.p_data,
				.init(planeBytesPerRow[0] * planeHeight[0] + planeBytesPerRow[1] * planeHeight[1]),
				2,
				planeBaseAddress,
				planeWidth,
				planeHeight,
				planeBytesPerRow,
				{ obj, mem, len, dim, adr in obj.map(UnsafeRawPointer.init).map(Unmanaged<NDIVideoFrame>.fromOpaque)?.release() },
				Unmanaged.passRetained(self).toOpaque(),
				.none,
				&result
			) == kCVReturnSuccess ? result : .none
		case NDIlib_FourCC_video_type_P216:
			var result: CVPixelBuffer?
			let planeProperties = UnsafeMutablePointer<Int>.allocate(capacity: 6)
			let planeWidth = planeProperties.advanced(by: 0)
			let planeHeight = planeProperties.advanced(by: 2)
			let planeBytesPerRow = planeProperties.advanced(by: 4)
			let planeBaseAddress = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 2)
			defer {
				planeProperties.deallocate()
				planeBaseAddress.deallocate()
			}
			planeWidth[0] = .init(ref.xres)
			planeWidth[1] = .init(ref.xres / 2)
			planeHeight[0] = .init(ref.yres)
			planeHeight[1] = .init(ref.yres / 2)
			planeBytesPerRow[0] = .init(ref.line_stride_in_bytes)
			planeBytesPerRow[1] = .init(ref.line_stride_in_bytes)
			planeBaseAddress[0] = .init(ref.p_data)
			planeBaseAddress[1] = .init(ref.p_data.advanced(by: planeBytesPerRow[0] * planeHeight[0]))
			return CVPixelBufferCreateWithPlanarBytes(
				kCFAllocatorDefault,
				.init(ref.xres),
				.init(ref.yres),
				kCVPixelFormatType_422YpCbCr16BiPlanarVideoRange,
				ref.p_data,
				.init(planeBytesPerRow[0] * planeHeight[0] + planeBytesPerRow[1] * planeHeight[1]),
				2,
				planeBaseAddress,
				planeWidth,
				planeHeight,
				planeBytesPerRow,
				{ obj, mem, len, dim, adr in obj.map(UnsafeRawPointer.init).map(Unmanaged<NDIVideoFrame>.fromOpaque)?.release() },
				Unmanaged.passRetained(self).toOpaque(),
				.none,
				&result
			) == kCVReturnSuccess ? result : .none
		case NDIlib_FourCC_video_type_I420:
			var result: CVPixelBuffer?
			let planeProperties = UnsafeMutablePointer<Int>.allocate(capacity: 9)
			let planeWidth = planeProperties.advanced(by: 0)
			let planeHeight = planeProperties.advanced(by: 3)
			let planeBytesPerRow = planeProperties.advanced(by: 6)
			let planeBaseAddress = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 3)
			defer {
				planeProperties.deallocate()
				planeBaseAddress.deallocate()
			}
			planeWidth[0] = .init(ref.xres)
			planeWidth[1] = .init(ref.xres / 2)
			planeWidth[2] = .init(ref.xres / 2)
			planeHeight[0] = .init(ref.yres)
			planeHeight[1] = .init(ref.yres / 2)
			planeHeight[2] = .init(ref.yres / 2)
			planeBytesPerRow[0] = .init(ref.line_stride_in_bytes)
			planeBytesPerRow[1] = .init(ref.line_stride_in_bytes / 2)
			planeBytesPerRow[2] = .init(ref.line_stride_in_bytes / 2)
			planeBaseAddress[0] = .init(ref.p_data)
			planeBaseAddress[1] = .init(ref.p_data.advanced(by: planeBytesPerRow[0] * planeHeight[0]))
			planeBaseAddress[2] = .init(ref.p_data.advanced(by: planeBytesPerRow[0] * planeHeight[0] + planeBytesPerRow[1] * planeHeight[1]))
			return CVPixelBufferCreateWithPlanarBytes(
				kCFAllocatorDefault,
				.init(ref.xres),
				.init(ref.yres),
				kCVPixelFormatType_420YpCbCr8PlanarFullRange,
				ref.p_data,
				.init(planeBytesPerRow[0] * planeHeight[0] + planeBytesPerRow[1] * planeHeight[1] + planeBytesPerRow[2] * planeHeight[2]),
				3,
				planeBaseAddress,
				planeWidth,
				planeHeight,
				planeBytesPerRow,
				{ obj, mem, len, dim, adr in obj.map(UnsafeRawPointer.init).map(Unmanaged<NDIVideoFrame>.fromOpaque)?.release() },
				Unmanaged.passRetained(self).toOpaque(),
				.none,
				&result
			) == kCVReturnSuccess ? result : .none
		case NDIlib_FourCC_video_type_NV12:
			var result: CVPixelBuffer?
			let planeProperties = UnsafeMutablePointer<Int>.allocate(capacity: 6)
			let planeWidth = planeProperties.advanced(by: 0)
			let planeHeight = planeProperties.advanced(by: 2)
			let planeBytesPerRow = planeProperties.advanced(by: 4)
			let planeBaseAddress = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 2)
			defer {
				planeProperties.deallocate()
				planeBaseAddress.deallocate()
			}
			planeWidth[0] = .init(ref.xres)
			planeWidth[1] = .init(ref.xres / 2)
			planeHeight[0] = .init(ref.yres)
			planeHeight[1] = .init(ref.yres / 2)
			planeBytesPerRow[0] = .init(ref.line_stride_in_bytes)
			planeBytesPerRow[1] = .init(ref.line_stride_in_bytes)
			planeBaseAddress[0] = .init(ref.p_data)
			planeBaseAddress[1] = .init(ref.p_data.advanced(by: planeBytesPerRow[0] * planeHeight[0]))
			return CVPixelBufferCreateWithPlanarBytes(
				kCFAllocatorDefault,
				.init(ref.xres),
				.init(ref.yres),
				kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
				ref.p_data,
				.init(planeBytesPerRow[0] * planeHeight[0] + planeBytesPerRow[1] * planeHeight[1]),
				2,
				planeBaseAddress,
				planeWidth,
				planeHeight,
				planeBytesPerRow,
				{ obj, mem, len, dim, adr in obj.map(UnsafeRawPointer.init).map(Unmanaged<NDIVideoFrame>.fromOpaque)?.release() },
				Unmanaged.passRetained(self).toOpaque(),
				.none,
				&result
			) == kCVReturnSuccess ? result : .none
		case NDIlib_FourCC_video_type_BGRX, NDIlib_FourCC_video_type_BGRA:
			var result: CVPixelBuffer?
			return CVPixelBufferCreateWithBytes(
				kCFAllocatorDefault,
				.init(ref.xres),
				.init(ref.yres),
				kCVPixelFormatType_32BGRA,
				ref.p_data,
				.init(ref.line_stride_in_bytes),
				{ obj, mem in obj.map(UnsafeRawPointer.init).map(Unmanaged<NDIVideoFrame>.fromOpaque)?.release() },
				Unmanaged.passRetained(self).toOpaque(),
				.none,
				&result
			) == kCVReturnSuccess ? result : .none
		case NDIlib_FourCC_video_type_RGBX, NDIlib_FourCC_video_type_RGBA:
			var result: CVPixelBuffer?
			return CVPixelBufferCreateWithBytes(
				kCFAllocatorDefault,
				.init(ref.xres),
				.init(ref.yres),
				kCVPixelFormatType_32RGBA,
				ref.p_data,
				.init(ref.line_stride_in_bytes),
				{ obj, mem in obj.map(UnsafeRawPointer.init).map(Unmanaged<NDIVideoFrame>.fromOpaque)?.release() },
				Unmanaged.passRetained(self).toOpaque(),
				.none,
				&result
			) == kCVReturnSuccess ? result : .none
		default:
			return nil
		}
	}
}
