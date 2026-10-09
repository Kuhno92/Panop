import Foundation
import Testing

/// Lets one real-engine test run at a time, across suites.
///
/// Swift Testing runs suites in parallel, and `.serialized` only orders the tests inside
/// one. libVLC, AVPlayer and LumeEngine all work with sockets, audio and threads of the
/// one test process, and libVLC tearing a player down in the background while another
/// engine opens a connection made that connection fail with an I/O error. In the app one
/// engine plays at a time, so serialising here matches how they are really used.
actor EngineLock {
    static let shared = EngineLock()

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

struct EngineGate: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // The suite-level call just runs its tests; each test case takes the lock.
        guard testCase != nil else {
            try await function()
            return
        }
        await EngineLock.shared.acquire()
        do {
            try await function()
        } catch {
            await EngineLock.shared.release()
            throw error
        }
        await EngineLock.shared.release()
    }
}

extension Trait where Self == EngineGate {
    static var engineGate: Self {
        Self()
    }
}

extension Trait where Self == ConditionTrait {
    /// For a test that plays real audio through libVLC and times what it reports: a hosted CI runner has no audio
    /// device
    /// (libVLC logs "AudioObjectAddPropertyListener failed"), so a state change comes late or not at all there. Run it
    /// on a
    /// Mac with sound.
    static var needsAudioDevice: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == nil,
            "needs an audio device, which a CI runner does not have"
        )
    }
}
