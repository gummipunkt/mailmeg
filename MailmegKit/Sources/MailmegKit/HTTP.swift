import Foundation

/// Abstraction over the network so the API clients can be tested without a server.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

enum FormEncoding {
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ parameters: [(String, String)]) -> Data {
        let body = parameters
            .map { key, value in "\(escape(key))=\(escape(value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    static func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
