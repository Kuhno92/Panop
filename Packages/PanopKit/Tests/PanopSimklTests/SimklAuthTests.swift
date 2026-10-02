import Foundation
import PanopCore
@testable import PanopSimkl
import Testing

private final class Replies: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, String)]
    private var seen: [HTTPRequest] = []

    init(_ replies: [(Int, String)]) {
        queue = replies
    }

    var requests: [HTTPRequest] {
        lock.withLock { seen }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let next = lock.withLock { () -> (Int, String) in
            seen.append(request)
            return queue.isEmpty ? (500, "") : queue.removeFirst()
        }
        return HTTPResponse(statusCode: next.0, body: Data(next.1.utf8))
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let response = try await send(request)
        return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks([response.body]))
    }
}

@Suite("Simkl sign-in")
struct SimklAuthTests {
    private let app = SimklApp(clientID: "cid", version: "1.0")
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let deviceReply = """
    {"device_code":"DEV","user_code":"BDWP-HQPK","verification_uri":"https://simkl.com/pin",
     "verification_uri_complete":"https://simkl.com/pin?user_code=BDWP-HQPK","expires_in":900,"interval":5}
    """
    private let tokenReply = #"{"access_token":"AT","refresh_token":"RT","token_type":"bearer","expires_in":604800}"#

    private func auth(_ replies: [(Int, String)]) -> (SimklAuth, Replies) {
        let transport = Replies(replies)
        return (SimklAuth(transport: transport, app: app), transport)
    }

    private func body(_ request: HTTPRequest) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: #require(request.body))
    }

    @Test
    func `a code is requested for reading and writing, with no secret`() async throws {
        let (auth, transport) = auth([(200, deviceReply)])

        let code = try await auth.requestCode(now: now)

        #expect(code.userCode == "BDWP-HQPK")
        #expect(code.verificationURLComplete?.absoluteString == "https://simkl.com/pin?user_code=BDWP-HQPK")
        #expect(code.expiresAt == now.addingTimeInterval(900))
        #expect(code.interval == 5)
        let request = try #require(transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path == "/oauth2/device")
        #expect(try body(request) == ["client_id": "cid", "scope": "media:read media:write"])
        #expect(request.headers["User-Agent"] == "panop/1.0")
    }

    @Test
    func `polling reports pending, slow down and expiry, then the tokens`() async throws {
        let (auth, transport) = auth([
            (200, deviceReply),
            (400, #"{"error":"authorization_pending"}"#),
            (400, #"{"error":"slow_down"}"#),
            (400, #"{"error":"expired_token"}"#),
            (200, tokenReply)
        ])
        let code = try await auth.requestCode(now: now)

        #expect(try await auth.poll(code, now: now) == .pending)
        #expect(try await auth.poll(code, now: now) == .slowDown(interval: 10))
        #expect(try await auth.poll(code, now: now) == .expired)
        let granted = try await auth.poll(code, now: now)

        #expect(granted == .granted(SimklTokens(
            accessToken: "AT", refreshToken: "RT", accessExpiresAt: now.addingTimeInterval(604_800)
        )))
        let last = try #require(transport.requests.last)
        #expect(try body(last)["grant_type"] == "urn:ietf:params:oauth:grant-type:device_code")
        #expect(try body(last)["device_code"] == "DEV")
    }

    @Test
    func `a refresh keeps the refresh token when the reply does not repeat it`() async throws {
        let (auth, _) = auth([(200, #"{"access_token":"NEW","expires_in":604800}"#)])
        let old = SimklTokens(accessToken: "AT", refreshToken: "RT", accessExpiresAt: now)

        let renewed = try await auth.refresh(old, now: now)

        #expect(renewed.accessToken == "NEW")
        #expect(renewed.refreshToken == "RT")
    }

    @Test
    func `a refused refresh means signed out`() async {
        let (auth, _) = auth([(400, #"{"error":"invalid_grant"}"#)])
        let old = SimklTokens(accessToken: "AT", refreshToken: "RT", accessExpiresAt: now)

        await #expect(throws: SimklAuthError.signedOut) { try await auth.refresh(old, now: now) }
    }

    @Test
    func `tokens count as expiring a day before the end`() {
        let tokens = SimklTokens(
            accessToken: "a",
            refreshToken: "r",
            accessExpiresAt: now.addingTimeInterval(86400 * 3)
        )

        #expect(!tokens.isExpiring(at: now))
        #expect(tokens.isExpiring(at: now.addingTimeInterval(86400 * 2 + 60)))
    }

    @Test
    func `revoking sends the refresh token and never throws`() async throws {
        let (auth, transport) = auth([(500, "")])
        let tokens = SimklTokens(accessToken: "AT", refreshToken: "RT", accessExpiresAt: now)

        await auth.revoke(tokens)

        let request = try #require(transport.requests.first)
        #expect(request.url.path == "/oauth2/revoke")
        #expect(try body(request)["token"] == "RT")
    }
}
