import Foundation
import PanopDiscover
import PanopSimkl

/// What the person's connected account added to the lists: Simkl's real rankings, and their own lists.
nonisolated struct AccountListsSnapshot: Codable, Equatable, Sendable {
    var rankedAt: Date?
    var customAt: Date?
    var plan: SimklPlan?
    var ranked: [CuratedList] = []
    var custom: [CuratedList] = []
}

/// Those lists, kept on disk and fetched rarely: the rankings daily (about 40 requests, and the account has
/// 500 a day), the person's own lists every six hours (a few). Fetched when the app opens or an account is
/// connected, never on a timer.
actor SimklAccountListsStore {
    static let rankedMaxAge: TimeInterval = 24 * 3600
    static let customMaxAge: TimeInterval = 6 * 3600
    /// The Settings switch for the person's own lists. On by default.
    static let customKey = "showSimklCustomLists"

    private let cacheURL: URL?

    init(cacheURL: URL? = SimklAccountListsStore.defaultCacheURL) {
        self.cacheURL = cacheURL
    }

    func cached() -> AccountListsSnapshot? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(AccountListsSnapshot.self, from: data)
    }

    /// Fetches what is out of date, and returns the snapshot if anything changed. A failure keeps what was
    /// there; a refused login is passed on so the caller can sign the person out.
    func refresh(
        client: SimklClient,
        wantsRanked: Bool,
        wantsCustom: Bool,
        now: Date = .now
    ) async throws -> AccountListsSnapshot? {
        var snapshot = cached() ?? AccountListsSnapshot()
        var changed = false
        if wantsRanked, snapshot.rankedAt.map({ now.timeIntervalSince($0) >= Self.rankedMaxAge }) ?? true {
            let ranked = try await SimklAccountLists.ranked(client: client)
            if !ranked.isEmpty {
                snapshot.ranked = ranked
                snapshot.rankedAt = now
                changed = true
            }
        }
        if wantsCustom, snapshot.customAt.map({ now.timeIntervalSince($0) >= Self.customMaxAge }) ?? true {
            if let made = try? await SimklAccountLists.custom(client: client) {
                snapshot.plan = made.plan
                snapshot.custom = made.lists
                snapshot.customAt = now
                changed = true
            }
        }
        guard changed else { return nil }
        save(snapshot)
        return snapshot
    }

    /// Forgets everything, for when the account is disconnected: these were that account's.
    func clear() {
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    private func save(_ snapshot: AccountListsSnapshot) {
        guard let cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Simkl", isDirectory: true)
            .appendingPathComponent("account-lists.json")
    }
}
