// What a card or widget shows for a countdown at a given moment: the words and the bar.
// Nothing here looks at the real clock; `now` is always passed in.

import Foundation

/// What one block of the bar is worth.
public enum BarUnit: String, CaseIterable, Sendable {
    case hour, day, week, month, year

    public var seconds: Int {
        switch self {
        case .hour: return 3600
        case .day: return 86400
        case .week: return 7 * 86400
        case .month: return 30 * 86400
        case .year: return 365 * 86400
        }
    }
}

/// The row of blocks under the time: one block per hour (or per day, week, ... for longer spans),
/// the last one partly filled.
public struct Bar: Equatable, Sendable {
    public var unit: BarUnit
    /// Whole blocks.
    public var full: Int
    /// How full the last block is, above 0 and below 1. Zero when there is no part block.
    public var partial: Double

    public init(unit: BarUnit, full: Int, partial: Double) {
        self.unit = unit
        self.full = full
        self.partial = partial
    }

    /// The most blocks ever drawn. A longer span moves up to a bigger unit.
    public static let maxBlocks = 24
    public static let empty = Bar(unit: .hour, full: 0, partial: 0)

    public var blocks: Int { full + (partial > 0 ? 1 : 0) }

    /// The bar for a span of `seconds`, using the smallest unit that needs at most `maxBlocks` blocks.
    public static func forSpan(seconds: Int) -> Bar {
        guard seconds > 0 else { return .empty }
        var unit = BarUnit.year
        for u in BarUnit.allCases where seconds <= u.seconds * maxBlocks {
            unit = u
            break
        }
        let full = seconds / unit.seconds
        if full >= maxBlocks { return Bar(unit: unit, full: maxBlocks, partial: 0) }
        return Bar(unit: unit, full: full, partial: Double(seconds % unit.seconds) / Double(unit.seconds))
    }
}

public enum DisplayState: String, Sendable {
    /// Counting.
    case running
    /// An all-day event whose day is today.
    case today
    /// A countdown that has ended.
    case finished
    /// Nothing to show (no countdown picked, or none exist).
    case empty
}

/// What a widget shows.
public struct WidgetDisplay: Equatable, Sendable {
    public var title: String
    public var timeText: String
    public var bar: Bar
    public var state: DisplayState
    public var mode: EventMode
    /// A short nudge under the time, such as "Tap to set again".
    public var hint: String?

    public init(title: String, timeText: String, bar: Bar, state: DisplayState, mode: EventMode, hint: String? = nil) {
        self.title = title
        self.timeText = timeText
        self.bar = bar
        self.state = state
        self.mode = mode
        self.hint = hint
    }

    /// Shown in the widget gallery and while a widget loads.
    public static func sample(mode: EventMode) -> WidgetDisplay {
        switch mode {
        case .countdown:
            return WidgetDisplay(title: "Done work", timeText: "6 hr, 15 min",
                                 bar: Bar(unit: .hour, full: 6, partial: 0.25), state: .running, mode: .countdown)
        case .since:
            return WidgetDisplay(title: "Started", timeText: "2 hr, 20 min",
                                 bar: Bar(unit: .hour, full: 2, partial: 1.0 / 3.0), state: .running, mode: .since)
        }
    }

    /// Shown when there is no countdown of this kind to pick.
    public static func nothing(mode: EventMode) -> WidgetDisplay {
        WidgetDisplay(title: mode == .countdown ? "No countdown" : "No time since",
                      timeText: "Open Curtain", bar: .empty, state: .empty, mode: mode)
    }
}

/// What a card in the app shows: a big line and a smaller one under it.
public struct CardDisplay: Equatable, Sendable {
    public var big: String
    public var detail: String
    public var state: DisplayState

    public init(big: String, detail: String, state: DisplayState) {
        self.big = big
        self.detail = detail
        self.state = state
    }
}

public enum Display {
    // MARK: Words

    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    /// "6 hr, 16 min": the two biggest parts, short enough for a Lock Screen widget.
    public static func compact(_ a: Amount) -> String {
        var parts: [String] = []
        if a.days > 0 { parts.append(plural(a.days, "day", "days")) }
        if a.hours > 0 { parts.append("\(a.hours) hr") }
        if a.minutes > 0 { parts.append("\(a.minutes) min") }
        if a.seconds > 0 { parts.append("\(a.seconds) sec") }
        return parts.prefix(2).joined(separator: ", ")
    }

    /// The big line and the small line of a card: "6 hours" over "21 mins, 13 secs".
    static func cardLines(_ a: Amount) -> (big: String, detail: String) {
        var big: [String] = []
        var small: [String] = []
        if a.days > 0 {
            big.append(plural(a.days, "day", "days"))
            small.append(plural(a.days, "day", "days"))
        }
        if a.hours > 0 {
            big.append(plural(a.hours, "hour", "hours"))
            small.append(plural(a.hours, "hr", "hrs"))
        }
        if a.minutes > 0 {
            big.append(plural(a.minutes, "min", "mins"))
            small.append(plural(a.minutes, "min", "mins"))
        }
        if a.seconds > 0 {
            big.append(plural(a.seconds, "sec", "secs"))
            small.append(plural(a.seconds, "sec", "secs"))
        }
        guard let first = big.first else { return ("", "") }
        return (first, small.dropFirst().prefix(2).joined(separator: ", "))
    }

    // MARK: Counting

    public static func isFinished(_ event: Event, now: Date, calendar: Calendar) -> Bool {
        guard event.mode == .countdown else { return false }
        if event.allDay { return Schedule.days(from: now, to: event.date, calendar: calendar) < 0 }
        return TimeMath.millisLeft(until: event.date, now: now) <= 0
    }

    /// The number a widget shows and the unit it was rounded to. Timed events only.
    /// Minutes up to a day; whole hours beyond that. Nil for a countdown that has ended.
    static func widgetCount(_ event: Event, now: Date) -> (units: Int, precision: Precision)? {
        switch event.mode {
        case .countdown:
            let m = TimeMath.unitsLeft(until: event.date, now: now, precision: .minutes)
            if m == 0 { return nil }
            if m > 1440 {
                return (TimeMath.unitsLeft(until: event.date, now: now, precision: .hours), .hours)
            }
            return (m, .minutes)
        case .since:
            let m = TimeMath.unitsPassed(since: event.date, now: now, precision: .minutes)
            if m >= 1440 {
                return (TimeMath.unitsPassed(since: event.date, now: now, precision: .hours), .hours)
            }
            return (m, .minutes)
        }
    }

    // MARK: Widget

    public static func widget(event: Event, now: Date, calendar: Calendar) -> WidgetDisplay {
        let finished = WidgetDisplay(title: event.name, timeText: "Finished", bar: .empty, state: .finished,
                                     mode: event.mode, hint: event.reusable ? "Tap to set again" : nil)
        if event.allDay {
            let d = event.mode == .countdown
                ? Schedule.days(from: now, to: event.date, calendar: calendar)
                : Schedule.days(from: event.date, to: now, calendar: calendar)
            if event.mode == .countdown && d < 0 { return finished }
            if d <= 0 {
                return WidgetDisplay(title: event.name, timeText: "Today", bar: .empty, state: .today, mode: event.mode)
            }
            return WidgetDisplay(title: event.name, timeText: plural(d, "day", "days"),
                                 bar: Bar.forSpan(seconds: d * 86400), state: .running, mode: event.mode)
        }
        guard let count = widgetCount(event, now: now) else { return finished }
        if count.units == 0 {
            return WidgetDisplay(title: event.name, timeText: "Just now", bar: .empty, state: .running, mode: event.mode)
        }
        let amount = TimeMath.split(count.units, precision: count.precision)
        return WidgetDisplay(title: event.name, timeText: compact(amount),
                             bar: Bar.forSpan(seconds: count.units * count.precision.rawValue),
                             state: .running, mode: event.mode)
    }

    /// The next moment after `t` at which `widget(event:now:)` gives something different.
    /// Nil when it never will (a countdown that has ended).
    public static func nextChange(event: Event, after t: Date, calendar: Calendar) -> Date? {
        if event.allDay {
            if event.mode == .countdown && Schedule.days(from: t, to: event.date, calendar: calendar) < 0 {
                return nil
            }
            return Schedule.startOfNextDay(after: t, calendar: calendar)
        }
        switch event.mode {
        case .countdown:
            let m = TimeMath.unitsLeft(until: event.date, now: t, precision: .minutes)
            if m == 0 { return nil }
            if m > 1440 {
                let h = TimeMath.unitsLeft(until: event.date, now: t, precision: .hours)
                return event.date.addingTimeInterval(-Double(h - 1) * 3600.0)
            }
            return event.date.addingTimeInterval(-Double(m - 1) * 60.0)
        case .since:
            let ms = TimeMath.millisPassed(since: event.date, now: t)
            if ms < 0 { return event.date }
            let m = Int(ms / 60_000)
            if m >= 1440 {
                let h = Int(ms / 3_600_000)
                return event.date.addingTimeInterval(Double(h + 1) * 3600.0)
            }
            return event.date.addingTimeInterval(Double(m + 1) * 60.0)
        }
    }

    // MARK: Card

    public static func card(event: Event, now: Date, showSeconds: Bool, calendar: Calendar) -> CardDisplay {
        if event.allDay {
            let w = widget(event: event, now: now, calendar: calendar)
            return CardDisplay(big: w.timeText, detail: "", state: w.state)
        }
        let precision: Precision = showSeconds ? .seconds : .minutes
        switch event.mode {
        case .countdown:
            let n = TimeMath.unitsLeft(until: event.date, now: now, precision: precision)
            if n == 0 { return CardDisplay(big: "Finished", detail: "", state: .finished) }
            let lines = cardLines(TimeMath.split(n, precision: precision))
            return CardDisplay(big: lines.big, detail: lines.detail, state: .running)
        case .since:
            let n = TimeMath.unitsPassed(since: event.date, now: now, precision: precision)
            if n == 0 { return CardDisplay(big: "Just now", detail: "", state: .running) }
            let lines = cardLines(TimeMath.split(n, precision: precision))
            return CardDisplay(big: lines.big, detail: lines.detail, state: .running)
        }
    }

    /// The bar for a card, the same one the widget draws.
    public static func bar(event: Event, now: Date, calendar: Calendar) -> Bar {
        widget(event: event, now: now, calendar: calendar).bar
    }
}
