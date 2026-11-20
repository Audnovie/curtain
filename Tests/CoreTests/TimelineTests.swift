import XCTest
@testable import CurtainCore

final class TimelineTests: XCTestCase {
    let cal = toronto()
    let end = at(2026, 11, 19, 21, 0)

    /// What iOS's own "relative" clock text reads at `now`, counting to or from `reference`: the
    /// biggest unit and the one under it, rounded down, a zero part left out. This is what the
    /// simulator was seen to print (ProbeUITests writes it down on every run).
    private func systemText(_ reference: Date, at now: Date) -> String {
        let a = TimeMath.split(Int(abs(reference.timeIntervalSince(now)).rounded(.down)), precision: .seconds)
        if a.days > 0 { return Display.compact(Amount(days: a.days, hours: a.hours)) }
        if a.hours > 0 { return Display.compact(Amount(hours: a.hours, minutes: a.minutes)) }
        return Display.compact(Amount(minutes: a.minutes, seconds: a.seconds))
    }

    /// What a widget following `plan` has on it at `t`, if iOS never comes back for another plan.
    private func shown(_ plan: TimelinePlan, at t: Date) -> String {
        guard let entry = plan.entries.last(where: { $0.date <= t }) else { return "(nothing)" }
        if let reference = entry.liveReference { return systemText(reference, at: t) }
        return entry.display.timeText
    }

    /// Entries come in order, and each holds exactly what is right at its own moment.
    private func assertSound(_ plan: TimelinePlan, _ event: Event, now: Date, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(plan.entries.isEmpty, file: file, line: line)
        XCTAssertLessThanOrEqual(plan.entries.count, TimelineBuilder.maxEntries + 5, file: file, line: line)
        XCTAssertEqual(plan.entries.first?.date, now, file: file, line: line)
        for (i, e) in plan.entries.enumerated() {
            XCTAssertEqual(Display.widget(event: event, now: e.date, calendar: cal), e.display,
                           "entry \(i) is wrong at its own moment", file: file, line: line)
            if i > 0 {
                XCTAssertGreaterThan(e.date, plan.entries[i - 1].date, "entry \(i) is out of order", file: file, line: line)
            }
        }
        if let reload = plan.reloadAfter {
            XCTAssertGreaterThan(reload, now, file: file, line: line)
        }
    }

    /// At every moment tried, the widget reads the same as our own words. Moments are taken
    /// across each gap between entries, including one second before the next entry.
    private func assertReadsRight(_ plan: TimelinePlan, _ event: Event, until last: Date,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var moments: [Date] = []
        for (i, e) in plan.entries.enumerated() {
            let next = i + 1 < plan.entries.count ? plan.entries[i + 1].date : last
            let gap = next.timeIntervalSince(e.date)
            guard gap > 0 else { continue }
            for fraction in [0.0, 0.25, 0.5, 0.75] { moments.append(e.date.addingTimeInterval(gap * fraction)) }
            if gap > 45 { moments.append(e.date.addingTimeInterval(37.3)) }
            if gap > 2 { moments.append(next.addingTimeInterval(-1)) }
        }
        var wrong = 0
        for t in moments where t <= last {
            // iOS's text ticks half a second before the minute on purpose (that has a test of
            // its own); stay clear of that half second here.
            let beforeTheMinute = event.date.timeIntervalSince(t).truncatingRemainder(dividingBy: 60)
            if event.mode == .countdown && beforeTheMinute > 0 && beforeTheMinute < 0.6 { continue }
            let want = Display.widget(event: event, now: t, calendar: cal).timeText
            let got = shown(plan, at: t)
            if got != want {
                wrong += 1
                if wrong <= 3 {
                    XCTFail("\(t.timeIntervalSince(plan.entries[0].date)) s in: shows \(got), should be \(want)", file: file, line: line)
                }
            }
        }
        XCTAssertEqual(wrong, 0, file: file, line: line)
    }

    func testShortCountdownIsPlannedToTheEnd() {
        let event = countdown(to: end)
        let now = end.addingTimeInterval(-hms(0, 10, 30))
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
        XCTAssertEqual(plan.entries.map { $0.display.timeText },
                       ["11 min", "10 min", "9 min", "8 min", "7 min", "6 min", "5 min", "4 min", "3 min",
                        "2 min", "1 min", "Finished"])
        XCTAssertEqual(plan.entries[1].date, at(2026, 11, 19, 20, 50))
        XCTAssertEqual(plan.entries[2].date, at(2026, 11, 19, 20, 51))
        XCTAssertEqual(plan.entries.last?.date, end)
        XCTAssertNil(plan.reloadAfter)
        // The last hour is all our own words: iOS's text would show seconds.
        XCTAssertTrue(plan.entries.allSatisfy { $0.liveReference == nil })
        assertSound(plan, event, now: now)
        assertReadsRight(plan, event, until: end.addingTimeInterval(hms(3)))
    }

    /// A whole shift is one plan. If iOS never asks again, the widget is still right all the way
    /// to "Finished" and stays there.
    func testAWholeShiftIsOnePlan() {
        let event = countdown(to: end)
        let now = end.addingTimeInterval(-hms(8)).addingTimeInterval(20)
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
        XCTAssertNil(plan.reloadAfter)
        XCTAssertEqual(plan.entries.count, 103)
        XCTAssertEqual(plan.entries.last?.display.state, .finished)
        XCTAssertEqual(plan.entries.last?.date, end)
        assertSound(plan, event, now: now)

        // Above an hour iOS's own text counts, towards a moment just under a minute past the end;
        // an entry every ten minutes moves the blocks.
        let counting = plan.entries.filter { $0.liveReference != nil }
        XCTAssertEqual(counting.count, 42)
        XCTAssertTrue(counting.allSatisfy { $0.liveReference == end.addingTimeInterval(59.5) })
        XCTAssertEqual(plan.entries[1].date, at(2026, 11, 19, 13, 10))
        XCTAssertEqual(plan.entries[2].date, at(2026, 11, 19, 13, 20))
        XCTAssertEqual(plan.entries[2].display.bar, Bar(unit: .hour, full: 7, partial: 40.0 / 60.0))

        // The last hour is minute by minute in our own words, every change on a clock minute.
        let lastHour = plan.entries.suffix(61)
        XCTAssertTrue(lastHour.allSatisfy { $0.liveReference == nil })
        XCTAssertEqual(lastHour.first?.date, at(2026, 11, 19, 20, 0))
        XCTAssertEqual(lastHour.prefix(3).map { $0.display.timeText }, ["1 hr", "59 min", "58 min"])
        XCTAssertEqual(lastHour.suffix(3).map { $0.display.timeText }, ["2 min", "1 min", "Finished"])
        for e in plan.entries.dropFirst() {
            XCTAssertEqual(e.date, Schedule.wholeMinute(e.date))
        }

        assertReadsRight(plan, event, until: end.addingTimeInterval(hms(5)))
        // The case this app was made for, on the widget. This one ends at 9:00 PM: at 6:50 it
        // says 2 hours 10 minutes, and at 8:50 it says 10 minutes, right through each minute.
        XCTAssertEqual(shown(plan, at: at(2026, 11, 19, 18, 50)), "2 hr, 10 min")
        XCTAssertEqual(shown(plan, at: at(2026, 11, 19, 18, 50, 59)), "2 hr, 10 min")
        XCTAssertEqual(shown(plan, at: at(2026, 11, 19, 20, 50)), "10 min")
        XCTAssertEqual(shown(plan, at: at(2026, 11, 19, 20, 50, 59)), "10 min")
        XCTAssertEqual(shown(plan, at: at(2026, 11, 19, 20, 51)), "9 min")
        XCTAssertEqual(shown(plan, at: at(2026, 11, 19, 23, 30)), "Finished")
    }

    /// iOS's text ticks over half a second before the clock does, never after it.
    func testTheSystemTextTicksJustBeforeTheMinute() {
        let event = countdown(to: end)
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: end.addingTimeInterval(-hms(5)), calendar: cal)
        let minute = at(2026, 11, 19, 17, 30)
        XCTAssertEqual(shown(plan, at: minute.addingTimeInterval(-0.6)), "3 hr, 31 min")
        XCTAssertEqual(shown(plan, at: minute.addingTimeInterval(-0.4)), "3 hr, 30 min")
        XCTAssertEqual(shown(plan, at: minute), "3 hr, 30 min")
    }

    func testWhereTheSystemTextIsUsed() {
        let down = countdown(to: end)
        func left(_ seconds: TimeInterval) -> Bool { TimelineBuilder.usesLiveText(down, at: end.addingTimeInterval(-seconds)) }
        XCTAssertFalse(left(hms(0, 59)))
        XCTAssertFalse(left(hms(1)))
        XCTAssertTrue(left(hms(1, 0, 1)))
        XCTAssertTrue(left(hms(23, 59)))
        XCTAssertFalse(left(hms(23, 59, 1)))
        XCTAssertFalse(left(hms(30)))
        XCTAssertFalse(left(-50))

        let began = at(2026, 11, 19, 9, 0)
        let up = since(from: began)
        func gone(_ seconds: TimeInterval) -> Bool { TimelineBuilder.usesLiveText(up, at: began.addingTimeInterval(seconds)) }
        XCTAssertFalse(gone(-50))
        XCTAssertFalse(gone(hms(0, 59, 59)))
        XCTAssertTrue(gone(hms(1)))
        XCTAssertTrue(gone(hms(23, 59, 59)))
        XCTAssertFalse(gone(hms(24)))
        XCTAssertEqual(TimelineBuilder.entry(up, at: began.addingTimeInterval(hms(2)), calendar: cal).liveReference, began)

        let allDay = countdown("Christmas", to: at(2026, 12, 25), allDay: true)
        XCTAssertFalse(TimelineBuilder.usesLiveText(allDay, at: at(2026, 12, 24, 22, 0)))
        XCTAssertNil(TimelineBuilder.liveReference(event: allDay, at: at(2026, 12, 24, 22, 0)))
    }

    func testPlansFromEveryDistanceReadRight() {
        let event = countdown(to: end)
        // From a few seconds to just over a day away.
        var seconds: TimeInterval = 7
        while seconds < hms(24, 30) {
            let now = end.addingTimeInterval(-seconds)
            let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
            assertSound(plan, event, now: now)
            XCTAssertEqual(plan.entries.last?.display.state, .finished, "\(seconds) s away")
            XCTAssertEqual(plan.entries.last?.date, end)
            if seconds <= hms(24) {
                XCTAssertNil(plan.reloadAfter, "\(seconds) s away")
                assertReadsRight(plan, event, until: end.addingTimeInterval(hms(2)))
            }
            seconds = seconds * 1.37 + 13
        }
    }

    func testADayAndABitAway() {
        let event = countdown(to: end)
        let now = end.addingTimeInterval(-hms(26, 0, 30))
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
        XCTAssertEqual(plan.entries.prefix(7).map { $0.display.timeText },
                       ["1 day, 3 hr", "1 day, 2 hr", "1 day, 1 hr", "1 day", "23 hr, 59 min", "23 hr", "22 hr"])
        XCTAssertEqual(plan.entries[3].date, end.addingTimeInterval(-hms(24)))
        XCTAssertEqual(plan.entries[4].date, end.addingTimeInterval(-hms(23, 59)))
        // More than a day out the words are ours; from 23 hr 59 min iOS's text takes over.
        XCTAssertTrue(plan.entries.prefix(4).allSatisfy { $0.liveReference == nil })
        XCTAssertEqual(plan.entries[4].liveReference, end.addingTimeInterval(59.5))
        // The last day is only roughed in (the blocks move hourly) and is planned again when it comes.
        XCTAssertEqual(plan.reloadAfter, end.addingTimeInterval(-hms(24)))
        XCTAssertEqual(plan.entries.count, 88)
        XCTAssertEqual(plan.entries.last?.display.state, .finished)
        assertSound(plan, event, now: now)
        // Even if iOS never comes back, the words are right all the way down.
        assertReadsRight(plan, event, until: end.addingTimeInterval(hms(2)))

        // Planned again with exactly a day to go: ten-minute steps this time.
        let dayLeft = end.addingTimeInterval(-hms(24))
        let again = TimelineBuilder.plan(event: event, mode: .countdown, now: dayLeft, calendar: cal)
        XCTAssertEqual(again.entries.prefix(3).map { $0.display.timeText }, ["1 day", "23 hr, 59 min", "23 hr, 50 min"])
        XCTAssertNil(again.entries[0].liveReference)
        XCTAssertEqual(again.entries.count, 200)
        XCTAssertNil(again.reloadAfter)
        assertSound(again, event, now: dayLeft)
        assertReadsRight(again, event, until: end.addingTimeInterval(hms(2)))
    }

    func testFarAwayCountdownChangesByTheHour() {
        let event = countdown(to: end)
        let now = end.addingTimeInterval(-hms(24 * 30 + 5, 12, 40))
        let plan = TimelineBuilder.plan(event: event, mode: .countdown, now: now, calendar: cal)
        XCTAssertEqual(plan.entries[0].display.timeText, "30 days, 6 hr")
        XCTAssertEqual(plan.entries[1].display.timeText, "30 days, 5 hr")
        XCTAssertEqual(plan.entries[1].date, end.addingTimeInterval(-hms(24 * 30 + 5)))
        XCTAssertEqual(plan.entries[2].date.timeIntervalSince(plan.entries[1].date), 3600)
        // There are too many hours to list. iOS is asked back two hours before they run out, and
        // if it is late its own text carries on, shifted by just under an hour to round up.
        let lastListed = plan.entries[TimelineBuilder.maxSlowEntries - 1]
        XCTAssertEqual(lastListed.display.timeText, "25 days, 7 hr")
        XCTAssertEqual(lastListed.liveReference, end.addingTimeInterval(3599.5))
        XCTAssertEqual(plan.reloadAfter, lastListed.date.addingTimeInterval(-2 * 3600))
        XCTAssertEqual(systemText(end.addingTimeInterval(3599.5), at: lastListed.date.addingTimeInterval(hms(3, 20))), "25 days, 4 hr")
        XCTAssertTrue(plan.entries.prefix(TimelineBuilder.maxSlowEntries - 1).allSatisfy { $0.liveReference == nil })
        // The end is still in the plan.
        XCTAssertEqual(plan.entries[TimelineBuilder.maxSlowEntries].display.timeText, "1 day")
        XCTAssertEqual(plan.entries.last?.display.state, .finished)
        XCTAssertEqual(plan.entries.count, 205)
        assertSound(plan, event, now: now)
    }

    func testTimeSince() {
        let began = at(2026, 11, 19, 9, 0)
        let event = since(from: began)
        let now = began.addingTimeInterval(hms(0, 30, 45))
        let plan = TimelineBuilder.plan(event: event, mode: .since, now: now, calendar: cal)
        XCTAssertEqual(plan.entries.count, TimelineBuilder.maxEntries)
        XCTAssertEqual(plan.entries.prefix(3).map { $0.display.timeText }, ["30 min", "31 min", "32 min"])
        XCTAssertEqual(plan.entries[1].date, at(2026, 11, 19, 9, 31))
        // The first hour in our own words, then iOS's text counting from the start.
        XCTAssertTrue(plan.entries.prefix(30).allSatisfy { $0.liveReference == nil })
        XCTAssertEqual(plan.entries[30].date, at(2026, 11, 19, 10, 0))
        XCTAssertEqual(plan.entries[30].liveReference, began)
        XCTAssertEqual(plan.entries[31].date, at(2026, 11, 19, 10, 10))
        let last = plan.entries[plan.entries.count - 1]
        XCTAssertEqual(last.display.timeText, "2 days, 7 hr")
        XCTAssertEqual(last.liveReference, began)
        XCTAssertEqual(plan.reloadAfter, last.date.addingTimeInterval(-2 * 3600))
        assertSound(plan, event, now: now)
        assertReadsRight(plan, event, until: last.date.addingTimeInterval(hms(30)))

        // Well past a day it changes by the hour.
        let later = TimelineBuilder.plan(event: event, mode: .since, now: began.addingTimeInterval(hms(50, 10)), calendar: cal)
        XCTAssertEqual(later.entries[0].display.timeText, "2 days, 2 hr")
        XCTAssertEqual(later.entries[1].date, began.addingTimeInterval(hms(51)))
        XCTAssertEqual(later.entries.count, TimelineBuilder.maxSlowEntries)
        assertSound(later, event, now: began.addingTimeInterval(hms(50, 10)))

        // Crossing a day.
        let nearly = began.addingTimeInterval(hms(23, 58, 30))
        let crossing = TimelineBuilder.plan(event: event, mode: .since, now: nearly, calendar: cal)
        XCTAssertEqual(crossing.entries.prefix(4).map { $0.display.timeText }, ["23 hr, 58 min", "1 day", "1 day, 1 hr", "1 day, 2 hr"])
        XCTAssertEqual(crossing.entries[0].liveReference, began)
        XCTAssertNil(crossing.entries[1].liveReference)
        assertSound(crossing, event, now: nearly)
        assertReadsRight(crossing, event, until: began.addingTimeInterval(hms(100)))

        // One that hasn't begun yet waits on "Just now".
        let early = began.addingTimeInterval(-hms(2))
        let waiting = TimelineBuilder.plan(event: event, mode: .since, now: early, calendar: cal)
        XCTAssertEqual(waiting.entries.prefix(3).map { $0.display.timeText }, ["Just now", "1 min", "2 min"])
        XCTAssertEqual(waiting.entries[1].date, at(2026, 11, 19, 9, 1))
        assertSound(waiting, event, now: early)
    }

    func testAllDay() {
        let christmas = countdown("Christmas", to: at(2026, 12, 25), allDay: true)
        let now = at(2026, 12, 22, 14, 0)
        let plan = TimelineBuilder.plan(event: christmas, mode: .countdown, now: now, calendar: cal)
        XCTAssertEqual(plan.entries.map { $0.display.timeText }, ["3 days", "2 days", "1 day", "Today", "Finished"])
        XCTAssertEqual(plan.entries.map { $0.date },
                       [at(2026, 12, 22, 14, 0), at(2026, 12, 23), at(2026, 12, 24), at(2026, 12, 25), at(2026, 12, 26)])
        // Asked back just after each midnight, in case the phone has changed time zone.
        XCTAssertEqual(plan.reloadAfter, at(2026, 12, 23, 0, 2))
        XCTAssertTrue(plan.entries.allSatisfy { $0.liveReference == nil })
        assertSound(plan, christmas, now: now)
        assertReadsRight(plan, christmas, until: at(2026, 12, 28))

        let over = TimelineBuilder.plan(event: christmas, mode: .countdown, now: at(2026, 12, 27, 9, 0), calendar: cal)
        XCTAssertEqual(over.entries.map { $0.display.timeText }, ["Finished"])
        XCTAssertNil(over.reloadAfter)

        let moved = since("Moved in", from: at(2026, 10, 30), allDay: true)
        let morning = at(2026, 10, 30, 8, 0)
        let up = TimelineBuilder.plan(event: moved, mode: .since, now: morning, calendar: cal)
        XCTAssertEqual(up.entries.prefix(4).map { $0.display.timeText }, ["Today", "1 day", "2 days", "3 days"])
        // The night the clocks go back is 25 hours long; the change still lands on midnight.
        XCTAssertEqual(up.entries[3].date, at(2026, 11, 2))
        XCTAssertEqual(up.entries.count, TimelineBuilder.maxSlowEntries)
        XCTAssertEqual(up.reloadAfter, at(2026, 10, 31, 0, 2))
        XCTAssertNil(up.entries.last?.liveReference)
        assertSound(up, moved, now: morning)
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
