import Foundation
@testable import Panop
import Testing

@Suite("Guide timeline")
struct GuideTimelineTests {
    /// 2026-10-03 20:10 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_971_800)

    private func timeline() -> GuideTimeline {
        GuideTimeline.around(now, hoursBefore: 1, hoursAfter: 11, pointsPerHour: 300)
    }

    @Test
    func `the axis starts on the half hour before now, an hour back, and runs to well after`() {
        let line = timeline()

        // 20:10 rounds down to 20:00, an hour back is 19:00.
        #expect(line.start.timeIntervalSince1970.truncatingRemainder(dividingBy: 1800) == 0)
        #expect(line.start == Date(timeIntervalSince1970: 1_790_971_800 - 600 - 3600))
        #expect(line.end > now.addingTimeInterval(10 * 3600))
        #expect(line.width > 11 * 300)
    }

    @Test
    func `a programme sits where its time is, as wide as it is long`() throws {
        let line = timeline()
        let start = line.start.addingTimeInterval(2 * 3600)

        let frame = try #require(line.frame(start: start, stop: start.addingTimeInterval(1800)))

        #expect(frame.x == 600)
        #expect(frame.width == 150)
    }

    @Test
    func `a programme that began before the axis is cut at its left edge`() throws {
        let line = timeline()

        let frame = try #require(line.frame(
            start: line.start.addingTimeInterval(-3600),
            stop: line.start.addingTimeInterval(1800)
        ))

        #expect(frame.x == 0)
        #expect(frame.width == 150, "only the half hour inside the axis is drawn")
    }

    @Test
    func `a programme that runs past the end is cut at the right edge`() throws {
        let line = timeline()

        let frame = try #require(line.frame(
            start: line.end.addingTimeInterval(-1800),
            stop: line.end.addingTimeInterval(3600)
        ))

        #expect(frame.x + frame.width == line.width)
    }

    @Test
    func `a programme wholly outside the axis is not drawn`() {
        let line = timeline()

        #expect(line
            .frame(start: line.start.addingTimeInterval(-7200), stop: line.start.addingTimeInterval(-3600)) == nil)
        #expect(line.frame(start: line.end.addingTimeInterval(60), stop: line.end.addingTimeInterval(3600)) == nil)
        #expect(line.frame(start: line.start.addingTimeInterval(100), stop: line.start.addingTimeInterval(100)) == nil)
    }

    @Test
    func `a very short programme is still wide enough to see`() throws {
        let line = timeline()
        let start = line.start.addingTimeInterval(3600)

        let frame = try #require(line.frame(start: start, stop: start.addingTimeInterval(30)))

        #expect(frame.width == GuideTimeline.minimumWidth)
    }

    @Test
    func `there is a mark every half hour, the whole hours told apart`() {
        let line = timeline()

        let ticks = line.ticks

        #expect(ticks.count >= 22)
        #expect(zip(ticks, ticks.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 1800 })
        #expect(ticks.first.map(GuideTimeline.isWholeHour) == true, "the axis starts on a whole hour here")
        #expect(ticks.dropFirst().first.map(GuideTimeline.isWholeHour) == false)
    }

    @Test
    func `now is a little way in from the left`() {
        let line = timeline()

        #expect(line.x(for: now) == (3600.0 + 600.0) / 3600.0 * 300.0)
        #expect(line.x(for: line.start.addingTimeInterval(-99)) == 0)
    }
}
