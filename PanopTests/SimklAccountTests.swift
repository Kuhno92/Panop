import Foundation
@testable import Panop
import PanopCore
import PanopSimkl
import Testing

private final class Script: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, String)]
    private(set) var paths: [String] = []

    init(_ replies: [(Int, String)]) {
        queue = replies
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let next = lock.withLock { () -> (Int, String) in
            paths.append(request.url.path)
            return queue.isEmpty ? (500, "") : queue.removeFirst()
        }
        return HTTPResponse(statusCode: next.0, body: Data(next.1.utf8))
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let response = try await send(request)
        return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks([response.body]))
    }
}

@Suite("Simkl account", .serialized, .engineGate)
@MainActor
struct SimklAccountTests {
    private let device = """
    {"device_code":"DEV","user_code":"ABCD-EFGH","verification_uri":"https://simkl.com/pin","expires_in":900,"interval":5}
    """
    private let granted = #"{"access_token":"AT","refresh_token":"RT","expires_in":604800}"#

    private struct Rig {
        var account: SimklAccount
        var script: Script
        var store: InMemorySimklTokenStore
    }

    private func makeRig(_ replies: [(Int, String)], tokens: SimklTokens? = nil) -> Rig {
        let script = Script(replies)
        let store = InMemorySimklTokenStore(tokens)
        let auth = SimklAuth(transport: script, app: SimklApp(clientID: "cid", version: "1"))
        let account = SimklAccount(auth: auth, store: store, sleep: { _ in await Task.yield() })
        return Rig(account: account, script: script, store: store)
    }

    private func settle(_ account: SimklAccount, until done: (SimklAccount.State) -> Bool) async {
        for _ in 0 ..< 200 where !done(account.state) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func `an account with no saved tokens starts signed out and one with them connected`() {
        #expect(makeRig([]).account.state == .signedOut)
        let saved = SimklTokens(
            accessToken: "a",
            refreshToken: "r",
            accessExpiresAt: .now.addingTimeInterval(86400 * 5)
        )
        #expect(makeRig([], tokens: saved).account.state == .connected)
    }

    @Test
    func `signing in shows the code, waits through pending, then keeps the tokens`() async {
        let rig = makeRig([
            (200, device), (400, #"{"error":"authorization_pending"}"#), (200, granted)
        ])

        await rig.account.signIn()
        guard case let .waiting(code) = rig.account.state else {
            Issue.record("no code shown: \(rig.account.state)")
            return
        }
        #expect(code.userCode == "ABCD-EFGH")
        await settle(rig.account) { $0 == .connected }

        #expect(rig.account.isConnected)
        #expect(rig.store.load()?.accessToken == "AT")
    }

    @Test
    func `an expired code is reported, not retried forever`() async {
        let rig = makeRig([(200, device), (400, #"{"error":"expired_token"}"#)])

        await rig.account.signIn()
        await settle(rig.account) { $0 == .failed(.codeExpired) }

        #expect(rig.account.state == .failed(.codeExpired))
        #expect(rig.store.load() == nil)
    }

    @Test
    func `signing out forgets the tokens at once and tells Simkl`() async {
        let saved = SimklTokens(
            accessToken: "a",
            refreshToken: "r",
            accessExpiresAt: .now.addingTimeInterval(86400 * 5)
        )
        let rig = makeRig([(200, "")], tokens: saved)

        await rig.account.signOut()

        #expect(rig.account.state == .signedOut)
        #expect(rig.store.load() == nil)
        #expect(rig.script.paths == ["/oauth2/revoke"])
    }

    @Test
    func `a token near its end is renewed once and kept`() async {
        let old = SimklTokens(accessToken: "old", refreshToken: "RT", accessExpiresAt: .now.addingTimeInterval(3600))
        let rig = makeRig([(200, #"{"access_token":"new","expires_in":604800}"#)], tokens: old)

        async let first = rig.account.accessToken()
        async let second = rig.account.accessToken()
        let tokens = await [first, second]

        #expect(tokens == ["new", "new"])
        #expect(rig.script.paths == ["/oauth2/token"], "two callers, one refresh")
        #expect(rig.store.load()?.accessToken == "new")
    }

    @Test
    func `a refused refresh signs the person out`() async {
        let old = SimklTokens(accessToken: "old", refreshToken: "RT", accessExpiresAt: .now.addingTimeInterval(3600))
        let rig = makeRig([(400, #"{"error":"invalid_grant"}"#)], tokens: old)

        #expect(await rig.account.accessToken() == nil)

        #expect(rig.account.state == .signedOut)
        #expect(rig.store.load() == nil)
    }

    @Test
    func `a refresh that cannot reach Simkl keeps the sign-in and the old token`() async {
        let old = SimklTokens(accessToken: "old", refreshToken: "RT", accessExpiresAt: .now.addingTimeInterval(3600))
        let rig = makeRig([(503, "")], tokens: old)

        #expect(await rig.account.accessToken() == "old")

        #expect(rig.account.isConnected)
        #expect(rig.store.load() == old)
    }
}
