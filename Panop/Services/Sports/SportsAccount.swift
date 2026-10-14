import Foundation
import Observation
import PanopCore
import PanopSports

/// Whether the person has a sportapi.ai key that works, and what is left of their day's requests.
///
/// One owner of the key: everything that calls the service asks `client`, which reads it afresh, so a key that was
/// replaced (here, or by another device through iCloud) is the one used. The state follows what the service says:
/// a refused key is `invalid`, a spent day is `limitReached` until the reset.
@MainActor
@Observable
final class SportsAccount {
    enum State: Equatable {
        case noKey
        case validating
        case ready
        /// The service refused the key.
        case invalid
        /// The day's requests are used up, until `resetsAt` if the service said when.
        case limitReached(resetsAt: Date?)
    }

    /// What came of entering a key.
    enum KeyResult: Equatable {
        case accepted
        /// The service does not know this key.
        case rejected
        /// The service could not be asked, so the key is neither accepted nor refused.
        case unreachable
    }

    private(set) var state: State
    /// What the service last said about the budget.
    private(set) var quota: SportsQuota?

    private let keyStore: any SportsKeyStore
    private let sync: SportsSyncStore
    private let transport: any HTTPTransport
    private let memory: SportsKeyMemory
    private let now: @Sendable () -> Date
    /// Whether the key is to travel through iCloud: the person's switch, and iCloud being on. Set by the app.
    @ObservationIgnored var syncsKey: @MainActor () -> Bool = { true }
    /// Called when the key is gone, so what was fetched with it can go too.
    @ObservationIgnored var onKeyRemoved: @MainActor () -> Void = {}

    init(
        keyStore: any SportsKeyStore,
        sync: SportsSyncStore,
        transport: any HTTPTransport,
        memory: SportsKeyMemory = SportsKeyMemory(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.keyStore = keyStore
        self.sync = sync
        self.transport = transport
        self.memory = memory
        self.now = now
        state = keyStore.load() == nil ? .noKey : .ready
    }

    var hasKey: Bool {
        state != .noKey
    }

    /// The client for what the person's key allows. It reads the key at each call.
    var client: SportsClient {
        SportsClient(transport: transport) { [keyStore] in keyStore.load() }
    }

    /// The last four characters, to show which key is in use without showing it.
    var maskedKey: String? {
        keyStore.load().map { "••••" + $0.suffix(4) }
    }

    /// Whether a request may go out for something the person did not ask for.
    var allowsBackgroundCalls: Bool {
        switch effectiveState {
        case .ready: !(quota?.isReserved ?? false)
        default: false
        }
    }

    /// Whether any request may go out at all (the person asked for it).
    var allowsCalls: Bool {
        effectiveState == .ready
    }

    /// The state, with a spent day counted as over once its reset has passed.
    var effectiveState: State {
        if case let .limitReached(resetsAt) = state, let resetsAt, resetsAt <= now() {
            return .ready
        }
        return state
    }

    // MARK: - The key

    /// Asks the service whether the key is good, and keeps it only if it is.
    func setKey(_ text: String) async -> KeyResult {
        guard let key = SportsKeySync.decode(Data(text.utf8)) else { return .rejected }
        let previous = state
        state = .validating
        let candidate = SportsClient(transport: transport) { key }
        do {
            let quota = try await candidate.validate()
            keyStore.save(key)
            self.quota = quota
            state = .ready
            reconcile()
            return .accepted
        } catch SportsError.unauthorized {
            state = previous == .validating ? .noKey : previous
            return .rejected
        } catch let SportsError.dailyLimit(resetsAt) {
            // The key is good, and the day's requests are spent: it is kept.
            keyStore.save(key)
            state = .limitReached(resetsAt: resetsAt)
            reconcile()
            return .accepted
        } catch {
            state = previous == .validating ? .noKey : previous
            return .unreachable
        }
    }

    /// The person took the key out. With the sync on, the record is marked so other devices let go of it as well.
    func removeKey() {
        keyStore.delete()
        if syncsKey() {
            sync.setKeyBlob(nil, removed: true)
        }
        memory.forget()
        quota = nil
        state = .noKey
        onKeyRemoved()
    }

    /// Brings this device's key and the record into line, as the person's setting says: a key goes to the record so
    /// other devices have it, one that arrived is taken into the Keychain, one taken out elsewhere is taken out here,
    /// and with the setting off the record is emptied. Safe to run any number of times.
    func reconcile() {
        let record = sync.keyRecord
        let action = SportsKeySync.decide(
            local: keyStore.load(),
            blob: record.blob,
            removed: record.removed,
            remembered: memory.digest,
            uploading: syncsKey()
        )
        switch action {
        case .none:
            if let blob = record.blob {
                memory.remember(SportsKeySync.digest(blob))
            }
        case let .upload(blob):
            sync.setKeyBlob(blob)
            memory.remember(SportsKeySync.digest(blob))
        case let .adopt(key):
            keyStore.save(key)
            if let blob = record.blob {
                memory.remember(SportsKeySync.digest(blob))
            }
            // The key that arrived is not known to work here: the first call finds out.
            state = .ready
            quota = nil
        case .removeLocal:
            keyStore.delete()
            memory.forget()
            quota = nil
            state = .noKey
            onKeyRemoved()
        case .withdraw:
            sync.setKeyBlob(nil)
            memory.forget()
        }
    }

    // MARK: - What the service says

    func note(_ quota: SportsQuota?) {
        guard let quota else { return }
        self.quota = quota
        if case .limitReached = state {
            state = .ready
        }
    }

    func noteFailure(_ error: SportsError) {
        switch error {
        case .unauthorized:
            if hasKey {
                state = .invalid
            }
        case let .dailyLimit(resetsAt):
            state = .limitReached(resetsAt: resetsAt ?? Self.nextMidnightUTC(after: now()))
        default:
            break
        }
    }

    /// The service counts a day in UTC.
    static func nextMidnightUTC(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
            ?? date.addingTimeInterval(24 * 3600)
    }
}
