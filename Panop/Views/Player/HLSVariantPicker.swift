import Foundation
import PanopPlayback
import PanopPlaylist

/// Gives LumeEngine a playlist naming one video stream instead of all of them; see
/// `HLSMultivariant` for why that is three times faster to start.
///
/// The result is a local file, because the engine opens an address and has no way to be handed
/// playlist text. Any failure here, from a slow server to an unexpected playlist, returns the
/// original address: this can only make a stream start faster, never stop it starting.
nonisolated enum HLSVariantPicker {
    struct Choice {
        /// What to open.
        let address: String
        /// A temporary file to delete once playback ends, when one was made.
        let file: URL?
    }

    /// A playlist is a few kilobytes. This only stops a server that answers with a film.
    private static let sizeLimit = 512 * 1024
    /// The picker is on the path to the first frame, so it is not allowed to be slow: past this
    /// the engine is given the original address and does the work itself.
    private static let timeout: TimeInterval = 4

    /// Options the engine needs to read a playlist from disk whose entries are on the network.
    static let formatOptions = [
        "protocol_whitelist": "file,http,https,tcp,tls,crypto",
        "allowed_extensions": "ALL"
    ]

    static func choose(for item: PlaybackItem, fetch: (URLRequest) async throws -> Data = fetchData) async -> Choice {
        let original = Choice(address: item.url, file: nil)
        guard let url = URL(string: item.url), ["http", "https"].contains(url.scheme?.lowercased()),
              url.path.lowercased().hasSuffix(".m3u8")
        else { return original }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (name, value) in item.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let agent = item.userAgent {
            request.setValue(agent, forHTTPHeaderField: "User-Agent")
        }
        guard let data = try? await fetch(request), data.count <= sizeLimit,
              let text = String(data: data, encoding: .utf8),
              let simplified = HLSMultivariant.simplified(text, base: url)
        else { return original }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("panop-\(UUID().uuidString).m3u8")
        do {
            try simplified.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return original
        }
        return Choice(address: file.absoluteString, file: file)
    }

    private static func fetchData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
