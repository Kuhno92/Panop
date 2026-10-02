import Foundation
import PanopCore

/// What a person is shown to approve the app on Simkl.
public struct SimklDeviceCode: Sendable, Equatable {
    /// The polling credential. Never shown, never logged.
    public var deviceCode: String
    /// Eight characters, as `XXXX-YYYY`, exactly as Simkl writes them.
    public var userCode: String
    public var verificationURL: URL
    /// The same page with the code already typed in.
    public var verificationURLComplete: URL?
    public var expiresAt: Date
    /// Seconds to wait between polls.
    public var interval: TimeInterval
}

public struct SimklTokens: Sendable, Equatable, Codable {
    public var accessToken: String
    public var refreshToken: String
    public var accessExpiresAt: Date

    public init(accessToken: String, refreshToken: String, accessExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
    }

    /// Renewed a day early, so a long sync does not meet the end halfway.
    public func isExpiring(at now: Date = .now) -> Bool {
        now.addingTimeInterval(86400) >= accessExpiresAt
    }
}

public enum SimklPoll: Sendable, Equatable {
    case pending
    /// Wait this many seconds between polls from now on.
    case slowDown(interval: TimeInterval)
    case expired
    case granted(SimklTokens)
}

public enum SimklAuthError: Error, Equatable {
    case status(Int)
    case undecodable
    /// The refresh token was refused: the person has to sign in again.
    case signedOut
}

/// Signing in to Simkl with the device flow (RFC 8628): the app shows a code, the person approves it
/// on their phone or computer, and the app polls. No client secret exists or is needed.
public struct SimklAuth: Sendable {
    static let host = "https://api.simkl.com"
    static let deviceGrant = "urn:ietf:params:oauth:grant-type:device_code"

    private let transport: any HTTPTransport
    private let app: SimklApp

    public init(transport: any HTTPTransport, app: SimklApp) {
        self.transport = transport
        self.app = app
    }

    public func requestCode(now: Date = .now) async throws -> SimklDeviceCode {
        let (status, body) = try await post("/oauth2/device", [
            "client_id": app.clientID, "scope": "media:read media:write"
        ])
        guard status == 200 else { throw SimklAuthError.status(status) }
        guard let reply = try? JSONDecoder().decode(DeviceReply.self, from: body),
              let page = URL(string: reply.verificationURI) else { throw SimklAuthError.undecodable }
        return SimklDeviceCode(
            deviceCode: reply.deviceCode,
            userCode: reply.userCode,
            verificationURL: page,
            verificationURLComplete: reply.verificationURIComplete.flatMap(URL.init(string:)),
            expiresAt: now.addingTimeInterval(reply.expiresIn),
            interval: max(reply.interval ?? 5, 1)
        )
    }

    /// One poll. Call no faster than the code's `interval`, and wait longer after `slowDown`.
    public func poll(_ code: SimklDeviceCode, now: Date = .now) async throws -> SimklPoll {
        let (status, body) = try await post("/oauth2/token", [
            "client_id": app.clientID, "device_code": code.deviceCode, "grant_type": Self.deviceGrant
        ])
        if status == 200 {
            return try .granted(tokens(from: body, now: now, keeping: nil))
        }
        switch errorName(in: body) {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(interval: code.interval + 5)
        case "expired_token": return .expired
        default: throw SimklAuthError.status(status)
        }
    }

    /// New tokens from the refresh token. A refusal means the person has to sign in again.
    public func refresh(_ tokens: SimklTokens, now: Date = .now) async throws -> SimklTokens {
        let (status, body) = try await post("/oauth2/token", [
            "client_id": app.clientID, "refresh_token": tokens.refreshToken, "grant_type": "refresh_token"
        ])
        if status == 400 || status == 401 {
            throw SimklAuthError.signedOut
        }
        guard status == 200 else { throw SimklAuthError.status(status) }
        return try self.tokens(from: body, now: now, keeping: tokens.refreshToken)
    }

    /// Ends this sign-in on Simkl's side. Best effort: a failure here must not keep the person signed in.
    public func revoke(_ tokens: SimklTokens) async {
        _ = try? await post("/oauth2/revoke", ["client_id": app.clientID, "token": tokens.refreshToken])
    }

    // MARK: - Wire

    private func post(_ path: String, _ fields: [String: String]) async throws -> (Int, Data) {
        guard let url = app.url(Self.host + path),
              let body = try? JSONSerialization.data(withJSONObject: fields) else { throw SimklAuthError.undecodable }
        let response = try await transport.send(HTTPRequest(
            url: url,
            headers: ["User-Agent": app.userAgent, "Content-Type": "application/json", "Accept": "application/json"],
            timeout: 20,
            method: "POST",
            body: body
        ))
        return (response.statusCode, response.body)
    }

    private func errorName(in body: Data) -> String? {
        (try? JSONDecoder().decode(ErrorReply.self, from: body))?.error
    }

    private func tokens(from body: Data, now: Date, keeping refreshToken: String?) throws -> SimklTokens {
        guard let reply = try? JSONDecoder().decode(TokenReply.self, from: body),
              let refresh = reply.refreshToken ?? refreshToken else { throw SimklAuthError.undecodable }
        return SimklTokens(
            accessToken: reply.accessToken,
            refreshToken: refresh,
            accessExpiresAt: now.addingTimeInterval(reply.expiresIn ?? 7 * 86400)
        )
    }
}

private struct DeviceReply: Decodable {
    var deviceCode: String
    var userCode: String
    var verificationURI: String
    var verificationURIComplete: String?
    var expiresIn: TimeInterval
    var interval: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TokenReply: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct ErrorReply: Decodable {
    var error: String
}
