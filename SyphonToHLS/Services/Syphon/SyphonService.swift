import Combine
import Observation
import Syphon

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
