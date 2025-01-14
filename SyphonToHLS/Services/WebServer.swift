import Foundation
import NWHTTPServer
import OSLog
import UniformTypeIdentifiers

struct InvalidHTTPMethod: Error {
	var method: HTTPMethod
}

struct InvalidPath: Error {}

private let queue = DispatchQueue(label: "HTTPFileServer")

actor WebServer {
	let directory: URL

	private let server: HTTPServer?

	private let logger = Logger(category: "WebServer")

	init(directory: URL) {
		self.directory = directory.standardized

		do {
			self.server = try HTTPServer(port: 6706, queue: queue) { [logger] request, response in
				do {
					guard request.method == .GET else { throw InvalidHTTPMethod(method: request.method) }
					
					let requestPath = String(request.url.drop(while: { $0 == "/" }))

					if requestPath.isEmpty {
						response.headers["Content-Type"] = "text/html"
						guard let file = Bundle.main.url(forResource: "index", withExtension: "html") else { throw InvalidPath() }
						let data = try Data(contentsOf: file)
						response.send(data)
					} else {
						let file = directory.appending(path: requestPath)

						guard file.path().hasPrefix(directory.path()) else {
							logger.error("invalid path: \(requestPath)")
							throw InvalidPath()
						}

						if let mimeType = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType {
							response.headers["Content-Type"] = mimeType
						}
						let data = try Data(contentsOf: file)

						response.send(data)
					}
				} catch {
					logger.error("\(request.url) failed: \(error)")
					throw error
				}
			}
		} catch {
			logger.error("failed to create server: \(error)")
			self.server = nil
		}
	}

	func start() {
		server?.resume()
	}

	func stop() {
		server?.suspend()
	}
}
