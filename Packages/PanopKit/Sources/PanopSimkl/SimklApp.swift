import Foundation

/// Who is calling: the three URL parameters and the `User-Agent` that Simkl asks of every request.
public struct SimklApp: Sendable, Equatable {
    /// The public id from the app's registration at Simkl. It identifies the app, it is not a secret.
    public var clientID: String
    public var name: String
    public var version: String

    public init(clientID: String, name: String = "panop", version: String) {
        self.clientID = clientID
        self.name = name
        self.version = version
    }

    public var userAgent: String {
        "\(name)/\(version)"
    }

    /// `address` with the identifying parameters added.
    func url(_ address: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: address) else { return nil }
        components.queryItems = query + [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "app-name", value: name),
            URLQueryItem(name: "app-version", value: version)
        ]
        return components.url
    }
}
