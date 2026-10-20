import Foundation

/// Why provider traffic is held back. Never carries an address: errors end up in logs.
public enum NetworkBlock: Error, Sendable, Equatable, CustomStringConvertible {
    /// The person asked for a VPN to be active, and none is.
    case vpnRequired
    /// Traffic is set to go through the app's own tunnel, and it is not up.
    case tunnelNotConnected

    public var description: String {
        switch self {
        case .vpnRequired: "A VPN is required, and none is active."
        case .tunnelNotConnected: "The VPN tunnel is not connected."
        }
    }
}

/// Fails closed: while `gate` names a reason, nothing is sent and the wrapped transport is never touched, so
/// a request cannot slip out on the plain network while the VPN is down.
public struct GuardedTransport: HTTPTransport {
    private let inner: any HTTPTransport
    private let gate: @Sendable () -> NetworkBlock?

    public init(_ inner: any HTTPTransport, gate: @escaping @Sendable () -> NetworkBlock?) {
        self.inner = inner
        self.gate = gate
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if let block = gate() {
            throw block
        }
        return try await inner.send(request)
    }

    public func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        if let block = gate() {
            throw block
        }
        return try await inner.stream(request)
    }
}
