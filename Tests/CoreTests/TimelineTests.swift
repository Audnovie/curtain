import XCTest
@testable import CurtainCore

final class TimelineTests: XCTestCase {
    let cal = toronto()
    let end = at(2026, 11, 19, 21, 0)

    /// Between any two entries the widget would show exactly what the earlier entry holds, and
    /// each entry holds exactly what is right at its own moment. So a widget that follows the
    /// plan is never wrong, not even for a second.
    private func assertFaithful(_ plan: TimelinePlan, _ event: Event, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(plan.entries.isEmpty, file: file, line: line)
        for (i, e) in plan.entries.enumerated() {
            XCTAssertEqual(Display.widget(event: event, now: e.date, calendar: cal), e.display,
                           "entry \(i) is wrong at its own moment", file: file, line: line)
            guard i + 1 < plan.entries.count else { continue }
            let next = plan.entries[i + 1]
            XCTAssertGreaterThan(next.date, e.date, file: file, line: line)
            XCTAssertNotEqual(next.display, e.display, "entry \(i + 1) changes nothing", file: file, line: line)
            let gap = next.date.timeIntervalSince(e.date)
            for fraction in [0.001, 0.5, 0.999] {
                let t = e.date.addingTimeInterval(gap * fraction)
                XCTAssertEqual(Display.widget(event: event, now: t, calendar: cal), e.display,
                               "between entries \(i) and \(i + 1)", file: file, line: line)
            }
            XCTAssertEqual(Display.widget(event: event, now: next.date.addingTimeInterval(-0.002), calendar: cal),
                           e.display, "just before entry \(i + 1)", file: file, line: line)
        }
    }

    func testShortCountdownIsPlannedToTheEnd() {
        let event = countdown(to: end)
        let now = end.addingTimeInterval(-hms(0, 10, 30))
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
        XCTAssertEqual(plan.entries.map { $0.display.timeText },
                       ["11 min", "10 min", "9 min", "8 min", "7 min", "6 min", "5 min", "4 min", "3 min",
                        "2 min", "1 min", "Finished"])
        XCTAssertEqual(plan.entries[0].date, now)
        XCTAssertEqual(plan.entries[1].date, at(2026, 11, 19, 20, 50))
        XCTAssertEqual(plan.entries[2].date, at(2026, 11, 19, 20, 51))
        XCTAssertEqual(plan.entries.last?.date, end)
        XCTAssertNil(plan.reloadAfter)
        XCTAssertTrue(plan.entries.allSatisfy { $0.liveReference == nil })
        assertFaithful(plan, event)
    }

    func testEveryChangeFallsOnAClockMinute() {
        let event = countdown(to: end)
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: end.addingTimeInterval(-hms(2, 30, 12)), calendar: cal)
        XCTAssertNil(plan.reloadAfter)
        XCTAssertEqual(plan.entries.count, 152)
        for e in plan.entries.dropFirst() {
            XCTAssertEqual(e.date, Schedule.wholeMinute(e.date))
        }
        assertFaithful(plan, event)
    }

    func testAnEightHourShiftComesInStretches() {
        let event = countdown(to: end)
        var now = end.addingTimeInterval(-hms(8)).addingTimeInterval(20)
        var reloads = 0
        var seen: [String] = []
        while true {
            let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
            assertFaithful(plan, event)
            XCTAssertLessThanOrEqual(plan.entries.count, TimelineBuilder.defaultMaxEntries)
            guard let reload = plan.reloadAfter else {
                seen += plan.entries.map { $0.display.timeText }
                XCTAssertEqual(plan.entries.last?.display.state, .finished)
                break
            }
            let last = plan.entries[plan.entries.count - 1]
            // The stretch stops with more than an hour to go, and iOS is asked back 20 minutes early.
            XCTAssertGreaterThanOrEqual(TimeMath.unitsLeft(until: end, now: last.date, precision: .minutes), 61)
            XCTAssertEqual(last.liveReference, end.addingTimeInterval(59.5))
            XCTAssertTrue(plan.entries.dropLast().allSatisfy { $0.liveReference == nil })
            XCTAssertEqual(reload, last.date.addingTimeInterval(-20 * 60))
            XCTAssertGreaterThan(reload, now)
            seen += plan.entries.filter { $0.date < reload }.map { $0.display.timeText }
            now = reload
            reloads += 1
            XCTAssertLessThan(reloads, 10)
        }
        XCTAssertEqual(reloads, 2)
        // Every minute from 8 hours down to nothing was shown, in order, with nothing skipped.
        var expected: [String] = []
        for m in stride(from: 480, through: 1, by: -1) {
            expected.append(Display.compact(TimeMath.split(m, precision: .minutes)))
        }
        expected.append("Finished")
        XCTAssertEqual(seen, expected)
    }

    func testAStretchNeverEndsInsideTheLastHour() {
        let event = countdown(to: end)
        for minutes in [180, 181, 200, 239, 240, 241, 300] {
            let now = end.addingTimeInterval(-Double(minutes) * 60 + 30)
            let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
            assertFaithful(plan, event)
            if minutes <= 179 {
                XCTAssertNil(plan.reloadAfter)
            } else {
                XCTAssertNotNil(plan.reloadAfter, "\(minutes) minutes")
                let left = TimeMath.unitsLeft(until: end, now: plan.entries[plan.entries.count - 1].date, precision: .minutes)
                XCTAssertGreaterThanOrEqual(left, 61, "\(minutes) minutes")
            }
        }
        // 179 minutes and under fit in one go.
        let whole = TimelineBuilder.plan(event: event, mode: .countdown, now: end.addingTimeInterval(-179 * 60 + 30), calendar: cal)
        XCTAssertNil(whole.reloadAfter)
        XCTAssertEqual(whole.entries.count, 180)
    }

    /// iOS's own "relative" clock text rounds down. Counting to the fallback date, it must read
    /// the same as our rounded-up countdown (apart from ticking over half a second early).
    func testLiveFallbackMatchesTheRule() {
        let event = countdown(to: end)
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: end.addingTimeInterval(-hms(5)), calendar: cal)
        guard let last = plan.entries.last, let reference = last.liveReference else {
            return XCTFail("no fallback on a stretch that stops early")
        }
        var t = last.date
        while t < end.addingTimeInterval(-hms(1)) {
            for into in [0.0, 20.0, 59.0] {
                let now = t.addingTimeInterval(into)
                let systemMinutes = Int((reference.timeIntervalSince(now) / 60).rounded(.down))
                XCTAssertEqual(systemMinutes, TimeMath.unitsLeft(until: end, now: now, precision: .minutes))
            }
            t = t.addingTimeInterval(60)
        }
        // Days away, the words show whole hours, so the fallback is shifted by just under an hour.
        let far = TimelineBuilder.plan(event: event, mode: .countdown, now: end.addingTimeInterval(-hms(24 * 30)), calendar: cal)
        XCTAssertEqual(far.entries.last?.liveReference, end.addingTimeInterval(3599.5))
    }

    func testFarAwayCountdownChangesByTheHour() {
        let event = countdown(to: end)
        let now = end.addingTimeInterval(-hms(24 * 30 + 5, 12, 40))
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
        XCTAssertEqual(plan.entries.count, TimelineBuilder.defaultMaxEntries)
        XCTAssertEqual(plan.entries[0].display.timeText, "30 days, 6 hr")
        XCTAssertEqual(plan.entries[1].display.timeText, "30 days, 5 hr")
        XCTAssertEqual(plan.entries[1].date, end.addingTimeInterval(-hms(24 * 30 + 5)))
        XCTAssertEqual(plan.entries[2].date.timeIntervalSince(plan.entries[1].date), 3600)
        let last = plan.entries[plan.entries.count - 1]
        XCTAssertEqual(plan.reloadAfter, last.date.addingTimeInterval(-2 * 3600))
        assertFaithful(plan, event)
    }

    func testCrossingFromDaysToHours() {
        let event = countdown(to: end)
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: end.addingTimeInterval(-hms(26, 0, 30)), calendar: cal)
        let texts = plan.entries.prefix(6).map { $0.display.timeText }
        XCTAssertEqual(texts, ["1 day, 3 hr", "1 day, 2 hr", "1 day, 1 hr", "1 day", "23 hr, 59 min", "23 hr, 58 min"])
        XCTAssertEqual(plan.entries[3].date, end.addingTimeInterval(-hms(24)))
        XCTAssertEqual(plan.entries[4].date, end.addingTimeInterval(-hms(23, 59)))
        assertFaithful(plan, event)
    }

    func testTimeSince() {
        let began = at(2026, 11, 19, 9, 0)
        let event = since(from: began)
        let now = began.addingTimeInterval(hms(0, 30, 45))
        let plan = TimelineBuilder.plan(event: event, mode: .since, now: now, calendar: cal)
        XCTAssertEqual(plan.entries.count, TimelineBuilder.defaultMaxEntries)
        XCTAssertEqual(plan.entries[0].display.timeText, "30 min")
        XCTAssertEqual(plan.entries[1].display.timeText, "31 min")
        XCTAssertEqual(plan.entries[1].date, at(2026, 11, 19, 9, 31))
        let last = plan.entries[plan.entries.count - 1]
        XCTAssertEqual(last.liveReference, began)
        XCTAssertEqual(plan.reloadAfter, last.date.addingTimeInterval(-20 * 60))
        assertFaithful(plan, event)

        // Well past a day it changes by the hour.
        let later = TimelineBuilder.plan(event: event, mode: .since, now: began.addingTimeInterval(hms(50, 10)), calendar: cal)
        XCTAssertEqual(later.entries[0].display.timeText, "2 days, 2 hr")
        XCTAssertEqual(later.entries[1].date, began.addingTimeInterval(hms(51)))
        assertFaithful(later, event)

        // Crossing a day.
        let crossing = TimelineBuilder.plan(event: event, mode: .since, now: began.addingTimeInterval(hms(23, 58, 30)), calendar: cal)
        XCTAssertEqual(crossing.entries.prefix(4).map { $0.display.timeText }, ["23 hr, 58 min", "23 hr, 59 min", "1 day", "1 day, 1 hr"])
        assertFaithful(crossing, event)
    }

    func testAllDay() {
        let christmas = countdown("Christmas", to: at(2026, 12, 25), allDay: true)
        let plan = TimelineBuilder.plan(event: christmas, mode: .countdown, now: at(2026, 12, 22, 14, 0), calendar: cal)
        XCTAssertEqual(plan.entries.map { $0.display.timeText }, ["3 days", "2 days", "1 day", "Today", "Finished"])
        XCTAssertEqual(plan.entries.map { $0.date },
                       [at(2026, 12, 22, 14, 0), at(2026, 12, 23), at(2026, 12, 24), at(2026, 12, 25), at(2026, 12, 26)])
        XCTAssertNil(plan.reloadAfter)
        assertFaithful(plan, christmas)

        let moved = since("Moved in", from: at(2026, 10, 30), allDay: true)
        let up = TimelineBuilder.plan(event: moved, mode: .since, now: at(2026, 10, 30, 8, 0), calendar: cal)
        XCTAssertEqual(up.entries.prefix(4).map { $0.display.timeText }, ["Today", "1 day", "2 days", "3 days"])
        // The night the clocks go back is 25 hours long; the change still lands on midnight.
        XCTAssertEqual(up.entries[3].date, at(2026, 11, 2))
        XCTAssertNotNil(up.reloadAfter)
        XCTAssertNil(up.entries.last?.liveReference)
        assertFaithful(up, moved)
    }

    func testNothingToShowAndAlreadyOver() {
        let none = TimelineBuilder.plan(event: nil, mode: .countdown, now: end, calendar: cal)
        XCTAssertEqual(none.entries.count, 1)
        XCTAssertEqual(none.entries[0].display.state, .empty)
        XCTAssertNil(none.reloadAfter)

        let over = TimelineBuilder.plan(event: countdown(to: end), mode: .countdown, now: end.addingTimeInterval(500), calendar: cal)
        XCTAssertEqual(over.entries.map { $0.display.timeText }, ["Finished"])
        XCTAssertNil(over.reloadAfter)
    }
}
