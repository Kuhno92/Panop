import Foundation
import PanopCore

/// The one door for traffic to the person's providers (playlists, guides, artwork, Simkl, stream pages).
///
/// Every such request is made through here, so a rule about the network (a VPN is required, a tunnel is
/// the only way out) is applied in one place and cannot be missed by a screen added later. A SwiftLint
/// rule bans `URLSession` and `URLSessionTransport` outside this folder for that reason.
final nonisolated class ProviderNetwork: @unchecked Sendable { // swiftlint:disable:this modifier_order
    static let shared = ProviderNetwork()

    private let lock = NSLock()
    private var blocked: NetworkBlock?

    /// What currently holds traffic back, if anything. Read on every request.
    var block: NetworkBlock? {
        lock.withLock { blocked }
    }

    func setBlock(_ reason: NetworkBlock?) {
        lock.withLock { blocked = reason }
    }

    /// Throws while traffic is held back.
    func requireOpen() throws {
        if let block {
            throw block
        }
    }

    /// The portable core's transport: fails closed while `block` is set.
    var transport: any HTTPTransport {
        GuardedTransport(URLSessionTransport(session: session)) { [self] in block }
    }

    private let session = URLSession(configuration: .default)

    /// A session with its own settings (artwork wants its own limits and no URL cache). Made here so that
    /// it, too, belongs to the one door.
    func makeSession(_ configuration: URLSessionConfiguration) -> URLSession {
        URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try requireOpen()
        return try await session.data(for: request)
    }
}
