// The one rule this app exists for.
//
// A countdown is rounded UP to the smallest unit shown, and a "time since" is rounded DOWN.
// The phone's clock hides its seconds, which is the same as rounding the time of day down, so
// with these two rules the clock and the number always add up:
//
//     countdown to 7:00 PM, clock shows 6:50  ->  "10 min"   (6:50 + 10 = 7:00)
//     time since 9:00 AM,   clock shows 9:10  ->  "10 min"   (9:00 + 10 = 9:10)
//
// The countdown still ends at exactly 7:00:00.

import Foundation

/// The smallest unit being shown. The raw value is its length in seconds.
public enum Precision: Int, Sendable {
    case seconds = 1
    case minutes = 60
    case hours = 3600
    case days = 86400
}

/// A length of time split into parts for display.
public struct Amount: Equatable, Sendable {
    public var days: Int
    public var hours: Int
    public var minutes: Int
    public var seconds: Int

    public init(days: Int = 0, hours: Int = 0, minutes: Int = 0, seconds: Int = 0) {
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }

    public var isZero: Bool { days == 0 && hours == 0 && minutes == 0 && seconds == 0 }
}

public enum TimeMath {
    // Whole milliseconds, so that sums of seconds never drift by a hair and round the wrong way.
    static func millis(_ date: Date, roundDown: Bool) -> Int64 {
        let x = date.timeIntervalSinceReferenceDate * 1000.0
        return Int64(roundDown ? x.rounded(.down) : x.rounded())
    }

    /// Milliseconds from `now` until `date`. Zero or less once `date` has come.
    public static func millisLeft(until date: Date, now: Date) -> Int64 {
        millis(date, roundDown: false) - millis(now, roundDown: true)
    }

    /// Milliseconds from `date` until `now`. Negative while `date` is still ahead.
    public static func millisPassed(since date: Date, now: Date) -> Int64 {
        millis(now, roundDown: true) - millis(date, roundDown: false)
    }

    /// Whole units left until `date`, rounded up. Zero once `date` has come.
    public static func unitsLeft(until date: Date, now: Date, precision: Precision) -> Int {
        let ms = millisLeft(until: date, now: now)
        if ms <= 0 { return 0 }
        let unit = Int64(precision.rawValue) * 1000
        return Int((ms + unit - 1) / unit)
    }

    /// Whole units gone by since `date`, rounded down. Zero if `date` is still ahead.
    public static func unitsPassed(since date: Date, now: Date, precision: Precision) -> Int {
        let ms = millisPassed(since: date, now: now)
        if ms <= 0 { return 0 }
        return Int(ms / (Int64(precision.rawValue) * 1000))
    }

    /// Splits a count of `precision` units into days, hours, minutes and seconds.
    public static func split(_ units: Int, precision: Precision) -> Amount {
        let n = max(0, units)
        switch precision {
        case .seconds:
            return Amount(days: n / 86400, hours: (n % 86400) / 3600, minutes: (n % 3600) / 60, seconds: n % 60)
        case .minutes:
            return Amount(days: n / 1440, hours: (n % 1440) / 60, minutes: n % 60)
        case .hours:
            return Amount(days: n / 24, hours: n % 24)
        case .days:
            return Amount(days: n)
        }
    }
}

/// Clock and calendar helpers.
public enum Schedule {
    /// The same moment with its seconds dropped.
    public static func wholeMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 60.0).rounded(.down) * 60.0)
    }

    /// Usual times in order, without repeats or nonsense, and not too many.
    public static func tidy(usualTimes: [Int]) -> [Int] {
        let valid = Set(usualTimes.filter { $0 >= 0 && $0 < 1440 })
        return Array(valid.sorted().prefix(Event.maxUsualTimes))
    }

    /// Minutes after midnight on the clock at `date`.
    public static func minuteOfDay(of date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The next moment the clock reads `minuteOfDay`, strictly after `now`: later today if that
    /// time is still ahead, otherwise tomorrow.
    public static func next(minuteOfDay: Int, after now: Date, calendar: Calendar) -> Date {
        var c = DateComponents()
        c.hour = minuteOfDay / 60
        c.minute = minuteOfDay % 60
        c.second = 0
        if let d = calendar.nextDate(after: now, matching: c, matchingPolicy: .nextTime,
                                     repeatedTimePolicy: .first, direction: .forward) {
            return wholeMinute(d)
        }
        return wholeMinute(now.addingTimeInterval(86400))
    }

    /// Where a brand-new countdown starts: the next full hour that is at least ten minutes away.
    public static func defaultCountdownDate(now: Date, calendar: Calendar) -> Date {
        var c = DateComponents()
        c.minute = 0
        c.second = 0
        let from = now.addingTimeInterval(10 * 60)
        if let d = calendar.nextDate(after: from, matching: c, matchingPolicy: .nextTime,
                                     repeatedTimePolicy: .first, direction: .forward) {
            return wholeMinute(d)
        }
        return wholeMinute(now.addingTimeInterval(3600))
    }

    public static func startOfNextDay(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        if let next = calendar.date(byAdding: .day, value: 1, to: start) {
            return calendar.startOfDay(for: next)
        }
        return start.addingTimeInterval(86400)
    }

    /// Calendar days from `a` to `b`: 0 for the same day, 1 for the next day, negative if `b` is earlier.
    public static func days(from a: Date, to b: Date, calendar: Calendar) -> Int {
        let x = calendar.startOfDay(for: a)
        let y = calendar.startOfDay(for: b)
        return calendar.dateComponents([.day], from: x, to: y).day ?? 0
    }

    // MARK: Saved days
    //
    // An all-day event is saved as noon UTC on its calendar day, not as "midnight here". Midnight
    // here is a different day somewhere else, so a day saved that way would slip when the phone
    // changed time zone. Noon UTC names the day itself.

    static func gregorian(in zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    static let utcCalendar = gregorian(in: TimeZone(secondsFromGMT: 0) ?? TimeZone.current)

    /// The saved form of the calendar day that `date` falls on, on `calendar`'s clock.
    public static func dayStamp(for date: Date, calendar: Calendar) -> Date {
        let local = gregorian(in: calendar.timeZone).dateComponents([.year, .month, .day], from: date)
        var c = DateComponents()
        c.year = local.year
        c.month = local.month
        c.day = local.day
        c.hour = 12
        return utcCalendar.date(from: c) ?? date
    }

    /// A saved day made exact. Does nothing to one that is already noon UTC.
    public static func tidy(dayStamp date: Date) -> Date {
        dayStamp(for: date, calendar: utcCalendar)
    }

    /// Where a saved day begins on `calendar`'s clock.
    public static func startOfDay(stamp: Date, calendar: Calendar) -> Date {
        let day = utcCalendar.dateComponents([.year, .month, .day], from: stamp)
        var c = DateComponents()
        c.year = day.year
        c.month = day.month
        c.day = day.day
        // Noon always exists; in a few places midnight doesn't on the day the clocks change.
        c.hour = 12
        guard let noon = gregorian(in: calendar.timeZone).date(from: c) else { return stamp }
        return calendar.startOfDay(for: noon)
    }
}
