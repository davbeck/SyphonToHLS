import Foundation
import NWHTTPServer
import UniformTypeIdentifiers

struct InvalidHTTPMethod: Error {
	var method: HTTPMethod
}

struct InvalidPath: Error {}

private let queue = DispatchQueue(label: "HTTPFileServer")

actor WebServer {
	let directory: URL

	init(directory: URL) {
		self.directory = directory.standardized
	}

	func start() {
		let server = try! HTTPServer(port: 6706, queue: queue) { request, response in
			guard request.method == .GET else { throw InvalidHTTPMethod(method: request.method) }

			let requestPath = String(request.url.drop(while: { $0 == "/" }))

			if requestPath.isEmpty {
				response.headers["Content-Type"] = "text/html"
				guard let file = Bundle.main.url(forResource: "index", withExtension: "html") else { throw InvalidPath() }
				let data = try Data(contentsOf: file)
				response.send(data)
			} else {
				let file = self.directory.appending(path: requestPath)

				guard file.path().hasPrefix(self.directory.path()) else { throw InvalidPath() }

				if let mimeType = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType {
					response.headers["Content-Type"] = mimeType
				}
				let data = try Data(contentsOf: file)

				response.send(data)
			}
		}

		server.resume()
	}
}
