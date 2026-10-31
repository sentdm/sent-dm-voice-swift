import Foundation

/// The one HTTP call the core makes, so tests and the app can supply their own transport.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPClient {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Where the SDK talks to Sent.
public enum SentAPI {
    public static let defaultBaseURL = URL(string: "https://api.sent.dm")!

    public static func url(_ baseURL: URL, path: String) -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)!
    }
}
