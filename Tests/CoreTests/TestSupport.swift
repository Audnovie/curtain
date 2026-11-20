import Foundation
import XCTest
@testable import CurtainCore

/// Toronto time: it has both a spring-forward and a fall-back day to test against.
func toronto() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Toronto")!
    return c
}

func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// A moment on the Toronto clock.
func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0, calendar: Calendar = toronto()) -> Date {
    calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

/// An all-day event is saved as its calendar day, taken here from the Toronto clock.
func saved(_ date: Date, allDay: Bool) -> Date {
    allDay ? Schedule.dayStamp(for: date, calendar: toronto()) : date
}

func countdown(_ name: String = "Done work", to date: Date, reusable: Bool = false, allDay: Bool = false,
               usual: [Int] = []) -> Event {
    Event(name: name, mode: .countdown, date: saved(date, allDay: allDay), allDay: allDay, reusable: reusable,
          usualTimes: usual, createdAt: at(2026, 11, 1, 9, 0))
}

func since(_ name: String = "Started", from date: Date, allDay: Bool = false) -> Event {
    Event(name: name, mode: .since, date: saved(date, allDay: allDay), allDay: allDay, createdAt: at(2026, 11, 1, 9, 0))
}

func hms(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> TimeInterval {
    TimeInterval(h * 3600 + m * 60 + s)
}
