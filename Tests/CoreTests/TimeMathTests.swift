import XCTest
@testable import CurtainCore

final class TimeMathTests: XCTestCase {
    let seven = at(2026, 11, 19, 19, 0)

    /// The case from the request: a countdown to exactly 7:00 PM must say 10 minutes at 6:50, not 9.
    func testTenMinutesAtSixFifty() {
        func left(_ h: Int, _ m: Int, _ s: Int, _ fraction: Double = 0) -> Int {
            TimeMath.unitsLeft(until: seven, now: at(2026, 11, 19, h, m, s).addingTimeInterval(fraction), precision: .minutes)
        }
        XCTAssertEqual(left(18, 50, 0), 10)
        XCTAssertEqual(left(18, 50, 30), 10)
        XCTAssertEqual(left(18, 50, 59, 0.999), 10)
        XCTAssertEqual(left(18, 51, 0), 9)
        XCTAssertEqual(left(18, 49, 59, 0.999), 11)
        XCTAssertEqual(left(18, 59, 0), 1)
        XCTAssertEqual(left(18, 59, 59, 0.999), 1)
        XCTAssertEqual(left(19, 0, 0), 0)
        XCTAssertEqual(left(19, 0, 5), 0)
    }

    /// For every moment in a day and a quarter: the clock (which hides its seconds) plus the
    /// minutes shown lands exactly on the end time.
    func testClockPlusCountdownAlwaysAddsUp() {
        let start = seven.addingTimeInterval(-hms(30))
        var checked = 0
        var offset = 0.0
        while offset < hms(30) {
            for fraction in [0.0, 0.25, 0.999] {
                let now = start.addingTimeInterval(offset + fraction)
                let shown = TimeMath.unitsLeft(until: seven, now: now, precision: .minutes)
                if shown == 0 { continue }
                let clock = Schedule.wholeMinute(now)
                XCTAssertEqual(clock.addingTimeInterval(Double(shown) * 60), seven,
                               "at \(now) the clock plus \(shown) min misses the end")
                checked += 1
            }
            offset += 7
        }
        XCTAssertGreaterThan(checked, 40_000)
    }

    /// The same for counting up: the start plus the minutes shown is what the clock reads.
    func testStartPlusTimeSinceAlwaysAddsUp() {
        let began = at(2026, 11, 19, 9, 0)
        var offset = 0.0
        while offset < hms(30) {
            for fraction in [0.0, 0.5, 0.999] {
                let now = began.addingTimeInterval(offset + fraction)
                let shown = TimeMath.unitsPassed(since: began, now: now, precision: .minutes)
                XCTAssertEqual(began.addingTimeInterval(Double(shown) * 60), Schedule.wholeMinute(now))
            }
            offset += 11
        }
    }

    func testOtherPrecisions() {
        let now = seven.addingTimeInterval(-hms(6, 21, 16))
        XCTAssertEqual(TimeMath.unitsLeft(until: seven, now: now, precision: .seconds), 6 * 3600 + 21 * 60 + 16)
        XCTAssertEqual(TimeMath.unitsLeft(until: seven, now: now.addingTimeInterval(0.4), precision: .seconds),
                       6 * 3600 + 21 * 60 + 16)
        XCTAssertEqual(TimeMath.unitsLeft(until: seven, now: now, precision: .minutes), 6 * 60 + 22)
        XCTAssertEqual(TimeMath.unitsLeft(until: seven, now: now, precision: .hours), 7)
        XCTAssertEqual(TimeMath.unitsLeft(until: seven, now: now, precision: .days), 1)
        XCTAssertEqual(TimeMath.unitsLeft(until: seven, now: seven.addingTimeInterval(-hms(6)), precision: .hours), 6)

        let began = at(2026, 11, 19, 9, 0)
        let later = began.addingTimeInterval(hms(26, 20, 59))
        XCTAssertEqual(TimeMath.unitsPassed(since: began, now: later, precision: .minutes), 26 * 60 + 20)
        XCTAssertEqual(TimeMath.unitsPassed(since: began, now: later, precision: .hours), 26)
        XCTAssertEqual(TimeMath.unitsPassed(since: began, now: later, precision: .days), 1)
        XCTAssertEqual(TimeMath.unitsPassed(since: began, now: began.addingTimeInterval(-30), precision: .minutes), 0)
    }

    func testSplit() {
        XCTAssertEqual(TimeMath.split(6 * 3600 + 21 * 60 + 16, precision: .seconds),
                       Amount(days: 0, hours: 6, minutes: 21, seconds: 16))
        XCTAssertEqual(TimeMath.split(6 * 1440 + 9 * 60 + 20, precision: .minutes), Amount(days: 6, hours: 9, minutes: 20))
        XCTAssertEqual(TimeMath.split(1440, precision: .minutes), Amount(days: 1))
        XCTAssertEqual(TimeMath.split(49, precision: .hours), Amount(days: 2, hours: 1))
        XCTAssertEqual(TimeMath.split(-3, precision: .minutes), Amount())
        XCTAssertTrue(Amount().isZero)
    }
}

final class ScheduleTests: XCTestCase {
    let cal = toronto()

    func testWholeMinute() {
        XCTAssertEqual(Schedule.wholeMinute(at(2026, 11, 19, 14, 44, 59).addingTimeInterval(0.9)), at(2026, 11, 19, 14, 44))
        XCTAssertEqual(Schedule.wholeMinute(at(2026, 11, 19, 14, 44)), at(2026, 11, 19, 14, 44))
    }

    func testNextUsualTime() {
        let sevenPM = 19 * 60
        XCTAssertEqual(Schedule.next(minuteOfDay: sevenPM, after: at(2026, 11, 19, 14, 44, 10), calendar: cal),
                       at(2026, 11, 19, 19, 0))
        // Already 7:00 on the dot, or later: tomorrow.
        XCTAssertEqual(Schedule.next(minuteOfDay: sevenPM, after: at(2026, 11, 19, 19, 0), calendar: cal),
                       at(2026, 11, 20, 19, 0))
        XCTAssertEqual(Schedule.next(minuteOfDay: sevenPM, after: at(2026, 11, 19, 21, 30), calendar: cal),
                       at(2026, 11, 20, 19, 0))
        XCTAssertEqual(Schedule.next(minuteOfDay: 0, after: at(2026, 12, 31, 23, 59, 59), calendar: cal),
                       at(2027, 1, 1, 0, 0))
    }

    func testNextUsualTimeAcrossClockChanges() {
        // Clocks go forward on 14 March 2027: 2:30 AM doesn't happen that night.
        let spring = Schedule.next(minuteOfDay: 2 * 60 + 30, after: at(2027, 3, 13, 23, 0), calendar: cal)
        let c = cal.dateComponents([.month, .day, .hour], from: spring)
        XCTAssertEqual(c.month, 3)
        XCTAssertEqual(c.day, 14)
        XCTAssertEqual(c.hour, 3)
        // 5 PM the same day is 17 real hours after midnight minus the lost hour.
        XCTAssertEqual(Schedule.next(minuteOfDay: 17 * 60, after: at(2027, 3, 14, 0, 0), calendar: cal)
            .timeIntervalSince(at(2027, 3, 14, 0, 0)), hms(16))

        // Clocks go back on 1 November 2026: 1:30 AM happens twice. The first one counts.
        let fall = Schedule.next(minuteOfDay: 90, after: at(2026, 10, 31, 22, 0), calendar: cal)
        XCTAssertEqual(fall, at(2026, 11, 1, 5, 30, calendar: utc()))
        XCTAssertEqual(Schedule.next(minuteOfDay: 17 * 60, after: at(2026, 11, 1, 0, 0), calendar: cal)
            .timeIntervalSince(at(2026, 11, 1, 0, 0)), hms(18))
    }

    func testDefaultCountdownDate() {
        XCTAssertEqual(Schedule.defaultCountdownDate(now: at(2026, 11, 19, 14, 39, 20), calendar: cal), at(2026, 11, 19, 15, 0))
        XCTAssertEqual(Schedule.defaultCountdownDate(now: at(2026, 11, 19, 14, 52), calendar: cal), at(2026, 11, 19, 16, 0))
        XCTAssertEqual(Schedule.defaultCountdownDate(now: at(2026, 11, 19, 23, 55), calendar: cal), at(2026, 11, 20, 1, 0))
    }

    func testDays() {
        XCTAssertEqual(Schedule.days(from: at(2026, 11, 19, 21, 0), to: at(2026, 12, 25), calendar: cal), 36)
        XCTAssertEqual(Schedule.days(from: at(2026, 11, 19, 0, 0), to: at(2026, 11, 19, 23, 59), calendar: cal), 0)
        XCTAssertEqual(Schedule.days(from: at(2026, 11, 19, 23, 59), to: at(2026, 11, 20, 0, 0), calendar: cal), 1)
        XCTAssertEqual(Schedule.days(from: at(2026, 11, 20), to: at(2026, 11, 19), calendar: cal), -1)
        // A 25-hour day and a 23-hour day are each still one day.
        XCTAssertEqual(Schedule.days(from: at(2026, 10, 31, 12, 0), to: at(2026, 11, 2, 12, 0), calendar: cal), 2)
        XCTAssertEqual(Schedule.days(from: at(2027, 3, 13, 12, 0), to: at(2027, 3, 15, 12, 0), calendar: cal), 2)
        XCTAssertEqual(Schedule.startOfNextDay(after: at(2026, 11, 1, 0, 30), calendar: cal), at(2026, 11, 2))
    }

    func testTidyUsualTimes() {
        XCTAssertEqual(Schedule.tidy(usualTimes: [1260, 1020, 1140, 1020, -5, 1440, 2000]), [1020, 1140, 1260])
        XCTAssertEqual(Schedule.tidy(usualTimes: Array(0..<30)).count, Event.maxUsualTimes)
        XCTAssertEqual(Schedule.minuteOfDay(of: at(2026, 11, 19, 19, 5, 40), calendar: cal), 19 * 60 + 5)
    }
}
