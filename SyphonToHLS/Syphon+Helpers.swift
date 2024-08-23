import Cocoa
import Combine
import Metal
import Syphon

struct ServerDescription: Identifiable {
	fileprivate var description: [String: Any]

	var id: String
	var appName: String
	var name: String
	var icon: NSImage?

	init?(description: Any) {
		guard
			let description = description as? [String: Any],
			let id = description[SyphonServerDescriptionUUIDKey] as? String,
			let appName = description[SyphonServerDescriptionAppNameKey] as? String,
			let name = description[SyphonServerDescriptionNameKey] as? String
		else {
			assertionFailure()
			return nil
		}

		self.description = description

		self.id = id
		self.appName = appName
		self.name = name
		self.icon = description[SyphonServerDescriptionIconKey] as? NSImage
	}
}

@Observable
@MainActor
final class SyphonService {
	private var observers: Set<AnyCancellable> = []

	let directory: SyphonServerDirectory

	var servers: [ServerDescription] = []

	private var observer: Task<Void, Never>?

	init(directory: SyphonServerDirectory = .shared()) {
		self.directory = directory

		self.updateServers()

		Publishers.MergeMany(
			NotificationCenter.default.publisher(for: .SyphonServerAnnounce, object: directory),
			NotificationCenter.default.publisher(for: .SyphonServerUpdate, object: directory),
			NotificationCenter.default.publisher(for: .SyphonServerRetire, object: directory)
		)
		.sink { [weak self] notification in
			self?.updateServers()
		}
		.store(in: &observers)
	}

	private func updateServers() {
		self.servers = directory.servers
			.compactMap { ServerDescription(description: $0) }
	}
}

class SyphonMetalClient: Syphon.SyphonMetalClient {
	let frames: AsyncStream<any MTLTexture>

	init(
		_ serverDescription: ServerDescription,
		device: any MTLDevice,
		options: [AnyHashable: Any]? = nil
	) {
		let (stream, continuation) = AsyncStream.makeStream(of: MTLTexture.self)

		self.frames = stream

		super.init(
			serverDescription: serverDescription.description,
			device: device,
			options: options,
			newFrameHandler: { client in
				guard let texture = client.newFrameImage() else { return }

				continuation.yield(texture)
			}
		)
	}
}
