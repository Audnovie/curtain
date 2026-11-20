// Plans what a widget shows and when.
//
// A widget can't run code every minute. It hands iOS a list of moments, each with what to show
// from then on, and iOS swaps them in. iOS decides when to come back for a new list, and it can
// be late. So a plan leans on that as little as it can:
//
// - While a countdown has between an hour and a day to go, the time is drawn by iOS's own
//   self-updating clock text, which needs no list at all. That text rounds down, so it is given
//   a moment just under a minute past the real end to count to, which makes it read as rounded
//   up. An entry every ten minutes keeps the row of blocks moving.
// - In the last hour that clock text would start showing seconds, so every minute gets its own
//   entry in our own words, down to "Finished" exactly at the end.
// - More than a day out, the words change once an hour and get an entry each time.
//
// Every plan for a countdown runs all the way to "Finished", even if iOS never comes back.

import Foundation

public struct PlanEntry: Equatable, Sendable {
    /// Show this from `date` on.
    public var date: Date
    /// The words and the bar at `date`.
    public var display: WidgetDisplay
    /// When set, the widget draws the time with iOS's self-updating "relative" clock text,
    /// counting to (or from) this date, in place of `display.timeText`.
    public var liveReference: Date?

    public init(date: Date, display: WidgetDisplay, liveReference: Date? = nil) {
        self.date = date
        self.display = display
        self.liveReference = liveReference
    }
}

public struct TimelinePlan: Equatable, Sendable {
    public var entries: [PlanEntry]
    /// When to ask iOS for a fresh plan. Nil when this one already covers everything.
    public var reloadAfter: Date?

    public init(entries: [PlanEntry], reloadAfter: Date?) {
        self.entries = entries
        self.reloadAfter = reloadAfter
    }
}

public enum TimelineBuilder {
    /// About the most entries one plan holds.
    public static let maxEntries = 200
    /// The most once-an-hour (or once-a-day) entries in one plan.
    public static let maxSlowEntries = 120
    /// Minutes between entries while iOS's own clock text is showing the time.
    static let liveStep = 10
    /// The same for a last day planned from far off. That day is planned again when it comes.
    static let coarseLiveStep = 60

    public static func plan(event: Event?, mode: EventMode, now: Date, calendar: Calendar) -> TimelinePlan {
        guard let event = event else {
            return TimelinePlan(entries: [PlanEntry(date: now, display: .nothing(mode: mode))], reloadAfter: nil)
        }
        if event.allDay { return allDayPlan(event, now: now, calendar: calendar) }
        switch event.mode {
        case .countdown: return countdownPlan(event, now: now, calendar: calendar)
        case .since: return sincePlan(event, now: now, calendar: calendar)
        }
    }

    /// True while the time is drawn by iOS's own clock text: from an hour up to a day.
    public static func usesLiveText(_ event: Event, at moment: Date) -> Bool {
        if event.allDay { return false }
        switch event.mode {
        case .countdown:
            let m = TimeMath.unitsLeft(until: event.date, now: moment, precision: .minutes)
            return m > 60 && m < 1440
        case .since:
            let m = TimeMath.unitsPassed(since: event.date, now: moment, precision: .minutes)
            return m >= 60 && m < 1440
        }
    }

    /// The date iOS's "relative" clock text should count to or from, so that it reads the same as
    /// our own words at `moment`. iOS rounds down. A countdown is shifted by just under one unit
    /// so that it comes out rounded up (and ticks over half a second before the clock does,
    /// never after).
    public static func liveReference(event: Event, at moment: Date) -> Date? {
        if event.allDay { return nil }
        switch event.mode {
        case .since:
            return event.date
        case .countdown:
            let m = TimeMath.unitsLeft(until: event.date, now: moment, precision: .minutes)
            return event.date.addingTimeInterval(m > 1440 ? 3599.5 : 59.5)
        }
    }

    /// What a widget draws at `moment`.
    public static func entry(_ event: Event, at moment: Date, calendar: Calendar) -> PlanEntry {
        PlanEntry(date: moment, display: Display.widget(event: event, now: moment, calendar: calendar),
                  liveReference: usesLiveText(event, at: moment) ? liveReference(event: event, at: moment) : nil)
    }

    // MARK: Countdown

    static func countdownPlan(_ event: Event, now: Date, calendar: Calendar) -> TimelinePlan {
        let end = event.date
        func make(_ t: Date) -> PlanEntry { entry(event, at: t, calendar: calendar) }
        func at(minutesLeft m: Int) -> Date { end.addingTimeInterval(-Double(m) * 60.0) }

        var entries = [make(now)]
        // Minutes left at the newest entry so far.
        var m = TimeMath.unitsLeft(until: end, now: now, precision: .minutes)
        if m == 0 { return TimelinePlan(entries: entries, reloadAfter: nil) }

        var reload: Date?
        var step = liveStep
        if m > 1440 {
            // More than a day: an entry each time the hours change, down to "1 day, 1 hr".
            var h = TimeMath.unitsLeft(until: end, now: now, precision: .hours) - 1
            while h >= 25 && entries.count < maxSlowEntries {
                entries.append(make(end.addingTimeInterval(-Double(h) * 3600.0)))
                h -= 1
            }
            if h >= 25 {
                // Too far off to list every hour. iOS is asked back before these run out; if it
                // is late, its own clock text carries on from the last one.
                let last = entries[entries.count - 1].date
                entries[entries.count - 1].liveReference = liveReference(event: event, at: last)
                reload = max(now.addingTimeInterval(60), last.addingTimeInterval(-2 * 3600))
            } else {
                reload = at(minutesLeft: 1440)
            }
            // The last day is only roughed in here. It is planned properly when it comes.
            step = coarseLiveStep
            entries.append(make(at(minutesLeft: 1440)))
            m = 1440
        }

        // The rest, as minutes left. From a day down to an hour iOS's clock text does the
        // counting; these entries only move the blocks.
        var marks: [Int] = []
        if m == 1440 { marks.append(1439) }
        var g = ((min(m, 1439) - 1) / step) * step
        while g > 60 {
            marks.append(g)
            g -= step
        }
        // The last hour, minute by minute, ending on "Finished".
        var k = min(m - 1, 60)
        while k >= 0 {
            marks.append(k)
            k -= 1
        }
        for left in marks {
            entries.append(make(at(minutesLeft: left)))
        }
        return TimelinePlan(entries: entries, reloadAfter: reload)
    }

    // MARK: Time since

    static func sincePlan(_ event: Event, now: Date, calendar: Calendar) -> TimelinePlan {
        let start = event.date
        func make(_ t: Date) -> PlanEntry { entry(event, at: t, calendar: calendar) }
        func at(minutesIn n: Int) -> Date { start.addingTimeInterval(Double(n) * 60.0) }

        var entries = [make(now)]
        // Whole minutes gone by. Zero if it hasn't begun yet.
        let passed = TimeMath.unitsPassed(since: start, now: now, precision: .minutes)

        // The first hour, minute by minute, in our own words (iOS's text would show seconds).
        var k = passed + 1
        while k < 60 {
            entries.append(make(at(minutesIn: k)))
            k += 1
        }
        // From an hour to a day iOS's clock text does the counting; these only move the blocks.
        var g = max(60, (passed / liveStep + 1) * liveStep)
        while g < 1440 {
            entries.append(make(at(minutesIn: g)))
            g += liveStep
        }
        // Past a day: an entry each time the hours change, as many as there is room for.
        var h = max(24, passed / 60 + 1)
        let room = max(1, min(maxSlowEntries - 1, maxEntries - entries.count))
        for _ in 0..<room {
            entries.append(make(at(minutesIn: h * 60)))
            h += 1
        }
        // Counting up never ends, so there is always a next plan to fetch. If iOS is late with
        // it, its own clock text carries on from the last entry.
        let last = entries[entries.count - 1].date
        entries[entries.count - 1].liveReference = liveReference(event: event, at: last)
        let reload = max(now.addingTimeInterval(60), last.addingTimeInterval(-2 * 3600))
        return TimelinePlan(entries: entries, reloadAfter: reload)
    }

    // MARK: All day

    static func allDayPlan(_ event: Event, now: Date, calendar: Calendar) -> TimelinePlan {
        var entries = [entry(event, at: now, calendar: calendar)]
        var t = now
        while entries.count < maxSlowEntries, let next = Display.nextChange(event: event, after: t, calendar: calendar) {
            entries.append(entry(event, at: next, calendar: calendar))
            t = next
        }
        // Midnights are listed well ahead, but iOS is asked back just after the next one anyway:
        // if the phone has changed time zone, midnight has moved.
        let reload: Date? = entries.count > 1 ? entries[1].date.addingTimeInterval(120) : nil
        return TimelinePlan(entries: entries, reloadAfter: reload)
    }
}
