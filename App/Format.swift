// Dates and times as words, and colours in and out of SwiftUI.

import SwiftUI
import UIKit
import CurtainCore

enum Fmt {
    private static func formatter(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.calendar = AppClock.calendar
        f.timeZone = AppClock.timeZone
        configure(f)
        return f
    }

    private static let timeFormatter = formatter {
        $0.dateStyle = .none
        $0.timeStyle = .short
    }
    private static let dayFormatter = formatter { $0.setLocalizedDateFormatFromTemplate("EEEMMMd") }
    private static let dayYearFormatter = formatter { $0.setLocalizedDateFormatFromTemplate("MMMdyyyy") }

    /// "9:00 PM"
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "2:45", the way the Lock Screen clock shows it (no AM or PM).
    static func clockDigits(_ date: Date) -> String {
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: Locale.autoupdatingCurrent) ?? "h:mm"
        let digitsOnly = pattern.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        return formatter { $0.dateFormat = digitsOnly }.string(from: date)
    }

    /// "5:00 PM" for 1020 minutes after midnight.
    static func time(minuteOfDay: Int) -> String {
        var c = DateComponents()
        c.year = 2001
        c.month = 1
        c.day = 1
        c.hour = minuteOfDay / 60
        c.minute = minuteOfDay % 60
        guard let d = AppClock.calendar.date(from: c) else { return "\(minuteOfDay / 60):\(minuteOfDay % 60)" }
        return time(d)
    }

    /// "Today", "Tomorrow", "Yesterday", or "Mon, Nov 23" (with the year if it isn't this one).
    static func day(_ date: Date, now: Date) -> String {
        let cal = AppClock.calendar
        switch Schedule.days(from: now, to: date, calendar: cal) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: break
        }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
        return (sameYear ? dayFormatter : dayYearFormatter).string(from: date)
    }

    /// The same, for the middle of a sentence: "today", "tomorrow", "Mon, Nov 23".
    static func dayInSentence(_ date: Date, now: Date) -> String {
        let d = day(date, now: now)
        return ["Today", "Tomorrow", "Yesterday"].contains(d) ? d.lowercased() : d
    }

    /// The small line on a card: "Ends 9:00 PM", "Ends Mon, Nov 23", "Since Nov 1", "Tap to set".
    static func cardCaption(_ event: Event, now: Date) -> String {
        let cal = AppClock.calendar
        let today = Schedule.days(from: now, to: event.date, calendar: cal) == 0
        let finished = Display.isFinished(event, now: now, calendar: cal)
        let when = today && !event.allDay ? time(event.date) : day(event.date, now: now)
        switch event.mode {
        case .since:
            return "Since " + (today && !event.allDay ? when : dayInSentence(event.date, now: now))
        case .countdown:
            if finished { return event.reusable ? "Tap to set again" : "Ended " + (today ? when : dayInSentence(event.date, now: now)) }
            if event.allDay {
                let d = day(event.date, now: now)
                return (d == "Today" || d == "Tomorrow") ? d : "On " + d
            }
            return "Ends " + (today ? when : dayInSentence(event.date, now: now))
        }
    }

    /// The full line in the detail sheet: "Ends today at 9:00 PM", "Began Mon, Nov 16 at 9:01 AM".
    static func longCaption(_ event: Event, now: Date) -> String {
        let finished = Display.isFinished(event, now: now, calendar: AppClock.calendar)
        let verb: String
        switch event.mode {
        case .since: verb = "Began"
        case .countdown: verb = finished ? "Ended" : "Ends"
        }
        let d = dayInSentence(event.date, now: now)
        return event.allDay ? "\(verb) \(d)" : "\(verb) \(d) at \(time(event.date))"
    }

    /// "in 4 hr, 16 min", for a time that a countdown could be set to.
    static func until(_ date: Date, now: Date) -> String {
        let m = TimeMath.unitsLeft(until: date, now: now, precision: .minutes)
        return "in " + Display.compact(TimeMath.split(m, precision: .minutes))
    }
}

extension RGB {
    /// A colour chosen in the system colour picker. Wide-gamut picks are brought into range.
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.init(r: Double(r), g: Double(g), b: Double(b))
        } else {
            self.init(r: 0.5, g: 0.5, b: 0.5)
        }
    }
}
