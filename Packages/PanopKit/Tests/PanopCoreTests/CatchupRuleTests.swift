import Foundation
import PanopCore
import Testing

@Suite("Catch-up addresses for M3U channels")
struct CatchupRuleTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = Date(timeIntervalSince1970: 1_700_003_600)
    let now = Date(timeIntervalSince1970: 1_700_090_000)

    @Test func `the type and the template decide the mode`() {
        #expect(CatchupRule(type: "append", source: "?utc={utc}")?.mode == .append)
        #expect(CatchupRule(type: "shift", source: nil)?.mode == .shift)
        #expect(CatchupRule(type: "flussonic-ts", source: nil)?.mode == .flussonic)
        #expect(CatchupRule(type: "xc", source: nil)?.mode == .xtream)
        #expect(CatchupRule(type: nil, source: "http://h/a?s={utc}")?.mode == .default)
        #expect(CatchupRule(type: "append", source: nil) == nil)
        #expect(CatchupRule(type: nil, source: nil) == nil)
        #expect(CatchupRule(type: "vod-magic", source: "x") == nil)
    }

    @Test func `a rule survives being saved as text`() {
        let rule = CatchupRule(mode: .append, source: "?a={utc}&b={duration}")
        #expect(CatchupRule(encoded: rule.encoded) == rule)
        #expect(CatchupRule(encoded: CatchupRule(mode: .shift).encoded) == CatchupRule(mode: .shift))
        #expect(CatchupRule(encoded: nil) == nil)
        #expect(CatchupRule(encoded: "nonsense") == nil)
    }

    @Test func `a default template is filled in whole`() {
        let rule = CatchupRule(mode: .default, source: "http://h/ch/{utc}/{duration}?now={lutc}&e=${utcend}")
        let url = rule.url(live: "http://h/ch/live.ts", start: start, end: end, now: now)
        #expect(url?.absoluteString == "http://h/ch/1700000000/3600?now=1700090000&e=1700003600")
    }

    @Test func `an appended template follows the live address`() {
        let rule = CatchupRule(mode: .append, source: "?utc={utc}&lutc={lutc}")
        let url = rule.url(live: "http://h/ch/1.ts", start: start, end: end, now: now)
        #expect(url?.absoluteString == "http://h/ch/1.ts?utc=1700000000&lutc=1700090000")
    }

    @Test func `shift adds utc and lutc to the live address`() {
        let plain = CatchupRule(mode: .shift).url(live: "http://h/1.ts", start: start, end: end, now: now)
        #expect(plain?.absoluteString == "http://h/1.ts?utc=1700000000&lutc=1700090000")
        let queried = CatchupRule(mode: .shift).url(live: "http://h/1.ts?token=a", start: start, end: end, now: now)
        #expect(queried?.absoluteString == "http://h/1.ts?token=a&utc=1700000000&lutc=1700090000")
    }

    @Test func `the date placeholders are in UTC`() {
        let rule = CatchupRule(mode: .default, source: "http://h/{Y}-{m}-{d}/{H}{M}{S}")
        #expect(rule.url(live: "", start: start, end: end, now: now)?.absoluteString == "http://h/2023-11-14/221320")
    }

    @Test func `flussonic builds its archive address`() {
        let rule = CatchupRule(mode: .flussonic)
        #expect(
            rule.url(live: "http://h:80/news/index.m3u8?token=1", start: start, end: end)?.absoluteString
                == "http://h:80/news/archive-1700000000-3600.m3u8?token=1"
        )
        #expect(
            rule.url(live: "http://h/news/mpegts", start: start, end: end)?.absoluteString
                == "http://h/news/archive-1700000000-3600.ts"
        )
    }

    @Test func `an xtream style address becomes the timeshift address`() {
        let rule = CatchupRule(mode: .xtream)
        #expect(
            rule.url(live: "http://p.example:8080/live/user/pass/4242.ts", start: start, end: end)?.absoluteString
                == "http://p.example:8080/timeshift/user/pass/60/2023-11-14:22-13/4242.ts"
        )
        #expect(rule.url(live: "http://p.example/just/one.ts", start: start, end: end) == nil)
    }
}
