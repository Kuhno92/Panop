import Foundation
@testable import Panop
import Testing

@Suite("Parental controls")
@MainActor
struct ParentalControlsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(_ store: InMemoryPINStore = InMemoryPINStore()) -> ParentalControls {
        ParentalControls(store: store)
    }

    @Test
    func `only four to six digits make a PIN`() {
        for good in ["1234", "12345", "123456", "0000"] {
            #expect(ParentalControls.isValid(good), "\(good)")
        }
        for bad in ["", "123", "1234567", "12a4", "12 4", "١٢٣٤", "12.4"] {
            #expect(!ParentalControls.isValid(bad), "\(bad)")
        }
    }

    @Test
    func `the right PIN is accepted and the PIN itself is never stored`() {
        let store = InMemoryPINStore()
        let controls = make(store)
        #expect(!controls.hasPIN)

        #expect(controls.setPIN("4821"))

        #expect(controls.hasPIN)
        #expect(controls.verify("4821", now: now) == .accepted)
        #expect(controls.verify("4822", now: now) == .wrong(triesLeft: 4))
        let saved = store.load()
        #expect(saved?.hash.count == 32, "a SHA-256 digest, not the digits")
        #expect(saved?.hash != Data("4821".utf8))
    }

    @Test
    func `a PIN that is not valid is refused and changes nothing`() {
        let controls = make()
        #expect(!controls.setPIN("12"))
        #expect(!controls.hasPIN)
    }

    @Test
    func `five wrong tries lock it, the wait doubles, and the right PIN does not work while locked`() {
        let controls = make()
        controls.setPIN("1111")
        for tries in 1 ... 4 {
            #expect(controls.verify("0000", now: now) == .wrong(triesLeft: 5 - tries))
        }

        #expect(controls.verify("0000", now: now) == .locked(until: now.addingTimeInterval(60)))
        #expect(controls.verify("1111", now: now.addingTimeInterval(30)) == .locked(until: now.addingTimeInterval(60)))

        let later = now.addingTimeInterval(61)
        #expect(controls.verify("0000", now: later) == .locked(until: later.addingTimeInterval(120)))
        #expect(controls.verify("1111", now: later.addingTimeInterval(121)) == .accepted)
        #expect(
            controls.verify("0000", now: later.addingTimeInterval(121)) == .wrong(triesLeft: 4),
            "success reset the count"
        )
    }

    @Test
    func `the lock never grows past a quarter of an hour`() {
        let controls = make()
        controls.setPIN("1111")
        var moment = now
        var longest: TimeInterval = 0
        for _ in 0 ..< 20 {
            if case let .locked(until) = controls.verify("0000", now: moment) {
                longest = max(longest, until.timeIntervalSince(moment))
                moment = until.addingTimeInterval(1)
            }
        }
        #expect(longest == 900)
    }

    @Test
    func `tries and the lock survive a restart`() {
        let store = InMemoryPINStore()
        let first = make(store)
        first.setPIN("1111")
        for _ in 0 ..< 5 {
            _ = first.verify("0000", now: now)
        }

        let second = make(store)

        #expect(second.hasPIN)
        #expect(second.verify("1111", now: now.addingTimeInterval(10)) == .locked(until: now.addingTimeInterval(60)))
    }

    @Test
    func `removing needs the current PIN`() {
        let controls = make()
        controls.setPIN("1111")

        #expect(controls.removePIN(current: "2222", now: now) == .wrong(triesLeft: 4))
        #expect(controls.hasPIN)
        #expect(controls.removePIN(current: "1111", now: now) == .accepted)
        #expect(!controls.hasPIN)
    }
}
