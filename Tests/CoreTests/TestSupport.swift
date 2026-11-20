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

func countdown(_ name: String = "Done work", to date: Date, reusable: Bool = false, allDay: Bool = false,
               usual: [Int] = []) -> Event {
    Event(name: name, mode: .countdown, date: date, allDay: allDay, reusable: reusable, usualTimes: usual,
          createdAt: at(2026, 11, 1, 9, 0))
}

func since(_ name: String = "Started", from date: Date, allDay: Bool = false) -> Event {
    Event(name: name, mode: .since, date: date, allDay: allDay, createdAt: at(2026, 11, 1, 9, 0))
}

func hms(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> TimeInterval {
    TimeInterval(h * 3600 + m * 60 + s)
}
