import CoreGraphics
import CoreImage
import Dependencies
import OSLog

final class NDIReceiver: @unchecked Sendable {
	let logger = Logger(category: "NDIReceiver")

	let ndi: NDI

	let pNDI_recv: NDIlib_recv_instance_t

	convenience init?(source: NDISource? = nil) {
		guard let ndi = NDI.shared else {
			return nil
		}

		self.init(ndi: ndi, source: source)
	}

	init(ndi: NDI, source: NDISource? = nil) {
		self.ndi = ndi

		var recv_desc = NDIlib_recv_create_v3_t(
			source_to_connect_to: source?.ref ?? NDIlib_source_t(),
			color_format: NDIlib_recv_color_format_UYVY_BGRA,
			bandwidth: NDIlib_recv_bandwidth_highest,
			allow_video_fields: true,
			p_ndi_recv_name: nil
		)
		pNDI_recv = NDIlib_recv_create_v3(&recv_desc)
	}

	deinit {
		NDIlib_recv_destroy(pNDI_recv)
	}

	func connect(name: String) async {
		guard let find = NDIFind(ndi: self.ndi) else { return }
		guard let source = await find.getSource(named: name) else { return }

		self.connect(source)
	}

	func connect(_ source: NDISource) {
		var sourceRef = source.ref

		NDIlib_recv_connect(pNDI_recv, &sourceRef)
	}

	func capture(types: Set<NDICaptureType> = Set(NDICaptureType.allCases), timeout: Duration = .zero) -> NDIFrame {
		// The descriptors
		var video_frame: NDIlib_video_frame_v2_t = .init(
			xres: 0,
			yres: 0,
			FourCC: .init(0),
			frame_rate_N: 0,
			frame_rate_D: 0,
			picture_aspect_ratio: 0,
			frame_format_type: .init(0),
			timecode: 0,
			p_data: nil,
			NDIlib_video_frame_v2_t.__Unnamed_union___Anonymous_field9(),
			p_metadata: nil,
			timestamp: 0
		)
		var audio_frame: NDIlib_audio_frame_v3_t = .init(
			sample_rate: 0,
			no_channels: 0,
			no_samples: 0,
			timecode: 0,
			FourCC: NDIlib_FourCC_audio_type_FLTP,
			p_data: nil,
			.init(),
			p_metadata: nil,
			timestamp: 0
		)
		var metadata_frame: NDIlib_metadata_frame_t = .init(
			length: 0,
			timecode: 0,
			p_data: nil
		)

		let frameType = withUnsafeMutablePointer(to: &video_frame) { video_frame in
			withUnsafeMutablePointer(to: &audio_frame) { audio_frame in
				withUnsafeMutablePointer(to: &metadata_frame) { metadata_frame in
					NDIlib_recv_capture_v3(
						pNDI_recv,
						types.contains(.video) ? video_frame : nil,
						types.contains(.audio) ? audio_frame : nil,
						types.contains(.metadata) ? metadata_frame : nil,
						.init(timeout.seconds * 1000)
					)
				}
			}
		}

		switch frameType {
		case NDIlib_frame_type_none:
			return .none
		case NDIlib_frame_type_video:
			let videoFrame = NDIVideoFrame(video_frame, receiver: self)

			return .video(videoFrame)
		case NDIlib_frame_type_audio:
//			logger.debug("Audio data received (\(audio_frame.no_samples) samples).")
			NDIlib_recv_free_audio_v3(pNDI_recv, &audio_frame)

			return .audio
		case NDIlib_frame_type_metadata:
			logger.debug("NDIlib_frame_type_metadata")
			NDIlib_recv_free_metadata(pNDI_recv, &metadata_frame)

			return .metadata
		case NDIlib_frame_type_status_change:
			logger.debug("Status changed")

			return .statusChange
		default:
			logger.debug("Other \(frameType.rawValue)")

			return .unknown
		}
	}
}

enum NDICaptureType: CaseIterable {
	case video
	case audio
	case metadata
}

enum NDIFrame {
	case none
	case video(NDIVideoFrame)
	case audio
	case metadata
	case statusChange
	case unknown
}
