import Foundation
import PanopCore

/// Client for an Xtream Codes panel's `player_api.php`.
///
/// Small responses (login, categories, one series, short EPG) are plain
/// `async` calls. The three big lists (live, movies, series) return
/// ``XtreamBatches`` so they can be persisted as they arrive.
public struct XtreamClient: Sendable {
    public let credentials: ProviderCredentials
    private let transport: any HTTPTransport
    private let root: URL

    /// - Throws: ``XtreamError/invalidBaseURL`` unless `credentials.baseURL` is
    ///   an http(s) URL with a host.
    public init(credentials: ProviderCredentials, transport: any HTTPTransport) throws {
        guard let root = Self.normalizedRoot(credentials.baseURL) else {
            throw XtreamError.invalidBaseURL
        }
        self.credentials = credentials
        self.transport = transport
        self.root = root
    }

    // MARK: - Account

    /// Verifies the login. Panels answer 200 with `auth: 0` for bad
    /// credentials, so the status code alone proves nothing.
    public func authenticate() async throws -> XtreamAccount {
        let data = try await fetch(action: nil)
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let info = object["user_info"] as? [String: Any]
        else {
            throw XtreamError.unexpectedResponse
        }

        let auth = Self.int(info["auth"])
        guard auth == 1 else { throw XtreamError.authenticationFailed }

        return XtreamAccount(
            username: (info["username"] as? String) ?? credentials.username,
            status: info["status"] as? String,
            expiresAt: Self.int(info["exp_date"])
                .flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
            isTrial: Self.int(info["is_trial"]) == 1,
            maxConnections: Self.int(info["max_connections"]),
            activeConnections: Self.int(info["active_cons"]),
            allowedFormats: (info["allowed_output_formats"] as? [String]) ?? []
        )
    }

    // MARK: - Categories

    public func liveCategories() async throws -> [XtreamCategory] {
        try await decodeList(action: "get_live_categories")
    }

    public func movieCategories() async throws -> [XtreamCategory] {
        try await decodeList(action: "get_vod_categories")
    }

    public func seriesCategories() async throws -> [XtreamCategory] {
        try await decodeList(action: "get_series_categories")
    }

    // MARK: - Big lists

    public func liveStreams(categoryID: String? = nil, batchSize: Int = 500) -> XtreamBatches<XtreamLiveStream> {
        batches(action: "get_live_streams", categoryID: categoryID, batchSize: batchSize)
    }

    public func movies(categoryID: String? = nil, batchSize: Int = 500) -> XtreamBatches<XtreamMovie> {
        batches(action: "get_vod_streams", categoryID: categoryID, batchSize: batchSize)
    }

    public func series(categoryID: String? = nil, batchSize: Int = 500) -> XtreamBatches<XtreamSeries> {
        batches(action: "get_series", categoryID: categoryID, batchSize: batchSize)
    }

    // MARK: - Detail

    public func seriesInfo(seriesID: Int) async throws -> XtreamSeriesInfo {
        let data = try await fetch(action: "get_series_info", extra: [("series_id", String(seriesID))])
        do {
            return try JSONDecoder().decode(XtreamSeriesInfo.self, from: data)
        } catch {
            throw XtreamError.unexpectedResponse
        }
    }

    /// The next few programmes on one channel. Cheap enough to call per channel
    /// while browsing; for a full guide use XMLTV instead.
    public func shortEPG(streamID: Int, limit: Int = 4) async throws -> [XtreamEPGListing] {
        let data = try await fetch(
            action: "get_short_epg",
            extra: [("stream_id", String(streamID)), ("limit", String(limit))]
        )
        do {
            let envelope = try JSONDecoder().decode(ShortEPGEnvelope.self, from: data)
            return envelope.listings.compactMap(\.value)
        } catch {
            throw XtreamError.unexpectedResponse
        }
    }

    // MARK: - Guide

    /// The panel's XMLTV guide. The credentials are in the query string, so
    /// treat the URL as a secret: never log it or put it in an error.
    public func guideURL() -> URL? {
        let query = ["username": credentials.username, "password": credentials.password]
            .sorted { $0.key < $1.key }
            .map { "\(Self.encodeQuery($0.key))=\(Self.encodeQuery($0.value))" }
            .joined(separator: "&")
        return URL(string: root.absoluteString + "/xmltv.php?" + query)
    }

    // MARK: - Stream URLs

    public enum LiveFormat: String, Sendable {
        case hls = "m3u8"
        case transportStream = "ts"
    }

    /// Where a live channel plays from through the panel. A row's
    /// `directSource`, when present, is the caller's to prefer or ignore.
    public func liveURL(streamID: Int, format: LiveFormat = .hls) -> URL? {
        streamURL(kind: "live", id: String(streamID), fileExtension: format.rawValue)
    }

    public func movieURL(streamID: Int, containerExtension: String?) -> URL? {
        streamURL(kind: "movie", id: String(streamID), fileExtension: containerExtension ?? "mp4")
    }

    public func episodeURL(episodeID: String, containerExtension: String?) -> URL? {
        streamURL(kind: "series", id: episodeID, fileExtension: containerExtension ?? "mp4")
    }

    // MARK: - Internals

    private func streamURL(kind: String, id: String, fileExtension: String) -> URL? {
        let segments = [kind, credentials.username, credentials.password, "\(id).\(fileExtension)"]
        let path = segments.map(Self.encodePathSegment).joined(separator: "/")
        return URL(string: root.absoluteString + "/" + path)
    }

    private func batches<Item: Decodable & Sendable>(
        action: String,
        categoryID: String?,
        batchSize: Int
    ) -> XtreamBatches<Item> {
        var extra: [(String, String)] = []
        if let categoryID {
            extra.append(("category_id", categoryID))
        }
        // An unusable base URL was rejected in init, so this cannot fail; the
        // fallback keeps the signature non-throwing for callers who iterate.
        let url = apiURL(action: action, extra: extra) ?? root
        return XtreamBatches(
            transport: transport,
            request: HTTPRequest(url: url),
            batchSize: max(1, batchSize),
            redact: redactor()
        )
    }

    private func fetch(action: String?, extra: [(String, String)] = []) async throws -> Data {
        guard let url = apiURL(action: action, extra: extra) else { throw XtreamError.invalidBaseURL }
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(url: url))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as XtreamError {
            throw error
        } catch {
            throw XtreamError.transport(message: redactor()(error.localizedDescription))
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw XtreamError.http(status: response.statusCode)
        }
        return response.body
    }

    private func decodeList<Item: Decodable & Sendable>(action: String) async throws -> [Item] {
        let data = try await fetch(action: action)
        var streamer = JSONArrayStreamer()
        do {
            let raws = try streamer.consume(data)
            try streamer.finish()
            let decoder = JSONDecoder()
            return raws.compactMap { try? decoder.decode(Item.self, from: $0) }
        } catch let failure as JSONArrayStreamer.Failure {
            throw failure == .truncated ? XtreamError.truncatedResponse : XtreamError.unexpectedResponse
        }
    }

    private func apiURL(action: String?, extra: [(String, String)]) -> URL? {
        var pairs: [(String, String)] = [("username", credentials.username), ("password", credentials.password)]
        if let action {
            pairs.append(("action", action))
        }
        pairs += extra
        // Built by hand: URLComponents leaves `+` and `&` unescaped in query
        // values, which corrupts a password containing either.
        let query = pairs.map { "\(Self.encodeQuery($0.0))=\(Self.encodeQuery($0.1))" }.joined(separator: "&")
        return URL(string: root.absoluteString + "/player_api.php?" + query)
    }

    /// Replaces credentials in a string, in both raw and percent-encoded form.
    private func redactor() -> @Sendable (String) -> String {
        let secrets = [credentials.username, credentials.password]
            .flatMap { [$0, Self.encodeQuery($0)] }
            .filter { !$0.isEmpty }
        return { text in
            secrets.reduce(text) { $0.replacingOccurrences(of: $1, with: "<redacted>") }
        }
    }

    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    private static func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func encodePathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Keeps scheme, host, port and any path prefix; drops the query, fragment
    /// and trailing slashes, since people paste whole `get.php?...` links.
    private static func normalizedRoot(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        var path = components.path
        // A pasted `.../player_api.php` or `.../get.php` names a script, not a directory.
        for script in ["/player_api.php", "/get.php"] where path.hasSuffix(script) {
            path.removeLast(script.count)
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path
        return components.url
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let number as Double: Int(number)
        case let text as String: Int(text)
        default: nil
        }
    }
}

private struct ShortEPGEnvelope: Decodable {
    var listings: [Lossy<XtreamEPGListing>]

    enum CodingKeys: String, CodingKey {
        case listings = "epg_listings"
    }
}

/// Decodes to nil instead of failing, so one broken element is dropped alone.
struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}
