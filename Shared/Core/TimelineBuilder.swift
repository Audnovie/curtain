// Plans what a widget shows and when.
//
// A widget can't run code every minute. Instead it hands iOS a list of moments, each with
// what to show from then on, and iOS swaps them in on time. This file builds that list:
// one entry for every moment the words or the bar change.
//
// A list can't be endless, so a long countdown is planned in stretches. Each stretch asks iOS
// to come back for the next one before it runs out, and its last entry is marked `liveReference`
// so the widget can fall back to a clock text that iOS itself keeps counting if the next
// stretch turns up late.

import Foundation

public struct PlanEntry: Equatable, Sendable {
    /// Show `display` from this moment on.
    public var date: Date
    public var display: WidgetDisplay
    /// Only on the last entry of a stretch that isn't the final one: the date for a live
    /// "relative" clock text that shows the same thing as `display` and keeps going.
    public var liveReference: Date?

    public init(date: Date, display: WidgetDisplay, liveReference: Date? = nil) {
        self.date = date
        self.display = display
        self.liveReference = liveReference
    }
}

public struct TimelinePlan: Equatable, Sendable {
    public var entries: [PlanEntry]
    /// When to ask for the next stretch. Nil when this plan covers everything there is to show.
    public var reloadAfter: Date?

    public init(entries: [PlanEntry], reloadAfter: Date?) {
        self.entries = entries
        self.reloadAfter = reloadAfter
    }
}

public enum TimelineBuilder {
    /// Entries per stretch. Three hours of a countdown that changes every minute.
    public static let defaultMaxEntries = 180
    /// A countdown's stretch never ends inside its last hour: the live fallback text would
    /// start showing seconds there.
    static let minutesKeptForLastStretch = 61

    public static func plan(event: Event?, mode: EventMode, now: Date, calendar: Calendar,
                            maxEntries: Int = defaultMaxEntries) -> TimelinePlan {
        guard let event = event else {
            return TimelinePlan(entries: [PlanEntry(date: now, display: .nothing(mode: mode))], reloadAfter: nil)
        }
        let cap = max(64, maxEntries)
        var entries = [PlanEntry(date: now, display: Display.widget(event: event, now: now, calendar: calendar))]
        var t = now
        var complete = false
        while true {
            guard let next = Display.nextChange(event: event, after: t, calendar: calendar) else {
                complete = true
                break
            }
            if entries.count >= cap { break }
            entries.append(PlanEntry(date: next, display: Display.widget(event: event, now: next, calendar: calendar)))
            t = next
        }
        if complete { return TimelinePlan(entries: entries, reloadAfter: nil) }

        // More to come after this stretch.
        if event.mode == .countdown && !event.allDay {
            while entries.count > 1, let last = entries.last,
                  TimeMath.unitsLeft(until: event.date, now: last.date, precision: .minutes) < minutesKeptForLastStretch {
                entries.removeLast()
            }
        }
        guard let last = entries.last else {
            return TimelinePlan(entries: entries, reloadAfter: now.addingTimeInterval(900))
        }
        entries[entries.count - 1].liveReference = liveReference(event: event, at: last.date)

        // Ask for the next stretch a little before this one runs out.
        let lead: TimeInterval
        if event.allDay {
            lead = 6 * 3600
        } else if let previous = entries.dropLast().last, last.date.timeIntervalSince(previous.date) > 90 {
            lead = 2 * 3600
        } else {
            lead = 20 * 60
        }
        let reload = max(now.addingTimeInterval(60), last.date.addingTimeInterval(-lead))
        return TimelinePlan(entries: entries, reloadAfter: reload)
    }

    /// A date such that iOS's own "relative" text, which rounds down, reads the same as our
    /// rounded-up countdown at `moment` and from then on.
    static func liveReference(event: Event, at moment: Date) -> Date? {
        if event.allDay { return nil }
        switch event.mode {
        case .since:
            return event.date
        case .countdown:
            let m = TimeMath.unitsLeft(until: event.date, now: moment, precision: .minutes)
            // Just short of one unit, so the text ticks over half a second before the clock does
            // rather than exactly with it.
            return event.date.addingTimeInterval(m > 1440 ? 3599.5 : 59.5)
        }
    }
}
