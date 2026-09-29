import Foundation

/// Parses XMLTV timestamps such as `20260929183000 +0200`.
///
/// Hand-rolled because a guide holds a million of these, each parsed twice,
/// and `DateFormatter` costs tens of microseconds per call. The arithmetic here
/// is a few dozen integer operations.
enum XMLTVDate {
    static func parse(_ text: String) -> Date? {
        var digits: [Int] = []
        digits.reserveCapacity(14)
        var utf8 = text.utf8.makeIterator()
        var pending: UInt8?

        // Leading digits: YYYY[MM[DD[HH[MM[SS]]]]]
        while let byte = utf8.next() {
            if byte >= 0x30, byte <= 0x39 {
                digits.append(Int(byte - 0x30))
            } else {
                pending = byte
                break
            }
        }
        guard [8, 10, 12, 14].contains(digits.count) else { return nil }

        func number(_ start: Int, _ length: Int) -> Int {
            guard start + length <= digits.count else { return 0 }
            return digits[start ..< start + length].reduce(0) { $0 * 10 + $1 }
        }
        let year = number(0, 4)
        let month = number(4, 2)
        let day = number(6, 2)
        let hour = number(8, 2)
        let minute = number(10, 2)
        let second = number(12, 2)
        guard (1 ... 12).contains(month), (1 ... 31).contains(day),
              hour <= 23, minute <= 59, second <= 60
        else { return nil }

        // Anything unrecognised after the digits reads as UTC, the DTD default.
        var offsetSeconds = 0
        var byte = pending
        while byte == 0x20 {
            byte = utf8.next()
        }
        if byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") {
            let sign = byte == UInt8(ascii: "-") ? -1 : 1
            var offsetDigits: [Int] = []
            while let next = utf8.next(), offsetDigits.count < 4 {
                if next >= 0x30, next <= 0x39 {
                    offsetDigits.append(Int(next - 0x30))
                } else if next != UInt8(ascii: ":") {
                    break
                }
            }
            if offsetDigits.count == 4 {
                offsetSeconds = sign * ((offsetDigits[0] * 10 + offsetDigits[1]) * 3600
                    + (offsetDigits[2] * 10 + offsetDigits[3]) * 60)
            } else if offsetDigits.count == 2 {
                offsetSeconds = sign * (offsetDigits[0] * 10 + offsetDigits[1]) * 3600
            }
        }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86400 + hour * 3600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let monthIndex = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
