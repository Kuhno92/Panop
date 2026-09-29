import Foundation
@testable import PanopEPG
import Testing

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: components) ?? .distantPast
}

@Suite("XMLTV dates")
struct XMLTVDateTests {
    @Test
    func `applies a positive offset`() {
        // 18:30 at +02:00 is 16:30 UTC.
        #expect(XMLTVDate.parse("20260929183000 +0200") == utc(2026, 9, 29, 16, 30))
    }

    @Test
    func `applies a negative offset across midnight`() {
        #expect(XMLTVDate.parse("20261231230000 -0500") == utc(2027, 1, 1, 4, 0))
    }

    /// The XMLTV DTD says a missing offset means UTC.
    @Test
    func `no offset means UTC`() {
        #expect(XMLTVDate.parse("20260929183000") == utc(2026, 9, 29, 18, 30))
    }

    @Test(arguments: [
        ("20260929183000 +02:00", utc(2026, 9, 29, 16, 30)),
        ("20260929183000 +02", utc(2026, 9, 29, 16, 30)),
        ("20260929183000+0200", utc(2026, 9, 29, 16, 30)),
        ("20260929183000  +0200", utc(2026, 9, 29, 16, 30)),
        ("20260929183000 +0530", utc(2026, 9, 29, 13, 0)),
        ("20260929183000 UTC", utc(2026, 9, 29, 18, 30)),
        ("20260929183000 Z", utc(2026, 9, 29, 18, 30))
    ])
    func `accepts offset spellings seen in the wild`(text: String, expected: Date) {
        #expect(XMLTVDate.parse(text) == expected)
    }

    @Test(arguments: [
        ("202609291830", utc(2026, 9, 29, 18, 30)),
        ("2026092918", utc(2026, 9, 29, 18, 0)),
        ("20260929", utc(2026, 9, 29))
    ])
    func `accepts shortened forms`(text: String, expected: Date) {
        #expect(XMLTVDate.parse(text) == expected)
    }

    @Test(arguments: [
        "",
        "abc",
        "2026",
        "202609",
        "20261329000000",
        "20260029000000",
        "20260929250000",
        "20260929126000"
    ])
    func `rejects unreadable input`(text: String) {
        #expect(XMLTVDate.parse(text) == nil)
    }

    @Test
    func `handles leap days and century rules`() {
        #expect(XMLTVDate.parse("20240229120000") == utc(2024, 2, 29, 12))
        #expect(XMLTVDate.parse("20000229000000") == utc(2000, 2, 29))
        #expect(XMLTVDate.parse("19700101000000") == Date(timeIntervalSince1970: 0))
        #expect(XMLTVDate.parse("19691231235959") == Date(timeIntervalSince1970: -1))
    }

    /// The integer calendar arithmetic replaces Foundation's, so check it
    /// against Foundation on every day across several years, leap ones included.
    @Test
    func `matches Foundation across many years`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var day = utc(1999, 1, 1)
        for _ in 0 ..< 366 * 12 {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let text = String(format: "%04d%02d%02d073000", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            #expect(XMLTVDate.parse(text) == day.addingTimeInterval(7.5 * 3600), "\(text)")
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
    }
}
