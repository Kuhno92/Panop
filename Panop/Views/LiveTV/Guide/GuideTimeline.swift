import Foundation

/// The stretch of time a guide grid draws, and where on it things go.
///
/// Pure arithmetic, so the layout can be tested without a screen: a programme becomes an offset and a
/// width along the time axis.
nonisolated struct GuideTimeline: Equatable, Sendable {
    var start: Date
    var end: Date
    var pointsPerHour: Double

    /// A programme narrower than this is still drawn, as a sliver, so it can be seen and pressed.
    static let minimumWidth = 6.0

    /// From a little before `now`, rounded down to the half hour, to some hours after it.
    static func around(
        _ now: Date,
        hoursBefore: Double = 1,
        hoursAfter: Double = 11,
        pointsPerHour: Double
    ) -> GuideTimeline {
        let half = 1800.0
        let floored = (now.timeIntervalSince1970 / half).rounded(.down) * half
        let start = Date(timeIntervalSince1970: floored - hoursBefore * 3600)
        return GuideTimeline(
            start: start,
            end: start.addingTimeInterval((hoursBefore + hoursAfter) * 3600 + (now.timeIntervalSince1970 - floored)),
            pointsPerHour: pointsPerHour
        )
    }

    var width: Double {
        end.timeIntervalSince(start) / 3600 * pointsPerHour
    }

    /// Where along the axis `date` falls, held inside it.
    func x(for date: Date) -> Double {
        let clamped = min(max(date, start), end)
        return clamped.timeIntervalSince(start) / 3600 * pointsPerHour
    }

    /// Where a programme sits: its left edge and its width, cut to the axis. Nil when it is wholly
    /// outside, which the grid does not draw.
    func frame(start programmeStart: Date, stop: Date) -> (x: Double, width: Double)? {
        guard stop > start, programmeStart < end, stop > programmeStart else { return nil }
        let left = x(for: programmeStart)
        let right = x(for: stop)
        return (left, max(right - left, Self.minimumWidth))
    }

    /// The marks along the top: every half hour from the first whole one.
    var ticks: [Date] {
        let half = 1800.0
        var tick = (start.timeIntervalSince1970 / half).rounded(.up) * half
        var found: [Date] = []
        while tick < end.timeIntervalSince1970 {
            found.append(Date(timeIntervalSince1970: tick))
            tick += half
        }
        return found
    }

    /// Whether the time is on the whole hour, which gets a stronger mark and its label.
    static func isWholeHour(_ date: Date) -> Bool {
        Int(date.timeIntervalSince1970) % 3600 == 0
    }
}
