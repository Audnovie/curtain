import XCTest
@testable import CurtainCore

final class DisplayTests: XCTestCase {
    let cal = toronto()
    let end = at(2026, 11, 19, 21, 0)

    private func text(left: TimeInterval) -> String {
        Display.widget(event: countdown(to: end), now: end.addingTimeInterval(-left), calendar: cal).timeText
    }

    private func text(passed: TimeInterval) -> String {
        let began = at(2026, 11, 10, 9, 0)
        return Display.widget(event: since(from: began), now: began.addingTimeInterval(passed), calendar: cal).timeText
    }

    func testCountdownWordsOnAWidget() {
        XCTAssertEqual(text(left: hms(6, 16, 0)), "6 hr, 16 min")
        XCTAssertEqual(text(left: hms(6, 16, 40)), "6 hr, 17 min")
        XCTAssertEqual(text(left: hms(6, 15, 59) + 0.5), "6 hr, 16 min")
        XCTAssertEqual(text(left: hms(6)), "6 hr")
        XCTAssertEqual(text(left: hms(0, 59, 10)), "1 hr")
        XCTAssertEqual(text(left: hms(0, 59, 0)), "59 min")
        XCTAssertEqual(text(left: hms(0, 10, 0)), "10 min")
        XCTAssertEqual(text(left: hms(0, 9, 30)), "10 min")
        XCTAssertEqual(text(left: 1), "1 min")
        XCTAssertEqual(text(left: 0.2), "1 min")
        XCTAssertEqual(text(left: 0), "Finished")
        XCTAssertEqual(text(left: -90), "Finished")
    }

    func testCountdownWordsPastADay() {
        XCTAssertEqual(text(left: hms(23, 59, 0)), "23 hr, 59 min")
        XCTAssertEqual(text(left: hms(23, 59, 1)), "1 day")
        XCTAssertEqual(text(left: hms(24)), "1 day")
        XCTAssertEqual(text(left: hms(24, 0, 1)), "1 day, 1 hr")
        XCTAssertEqual(text(left: hms(25)), "1 day, 1 hr")
        XCTAssertEqual(text(left: hms(25, 0, 1)), "1 day, 2 hr")
        XCTAssertEqual(text(left: hms(47, 30)), "2 days")
        XCTAssertEqual(text(left: hms(6 * 24 + 9, 20)), "6 days, 10 hr")
        XCTAssertEqual(text(left: hms(400 * 24)), "400 days")
    }

    func testTimeSinceWordsOnAWidget() {
        XCTAssertEqual(text(passed: 0), "Just now")
        XCTAssertEqual(text(passed: 59), "Just now")
        XCTAssertEqual(text(passed: 60), "1 min")
        XCTAssertEqual(text(passed: hms(0, 10, 59)), "10 min")
        XCTAssertEqual(text(passed: hms(2, 20, 30)), "2 hr, 20 min")
        XCTAssertEqual(text(passed: hms(3)), "3 hr")
        XCTAssertEqual(text(passed: hms(23, 59, 59)), "23 hr, 59 min")
        XCTAssertEqual(text(passed: hms(24)), "1 day")
        XCTAssertEqual(text(passed: hms(3 * 24 + 4, 59)), "3 days, 4 hr")
        // Not begun yet (the clock was changed): never negative.
        XCTAssertEqual(text(passed: -500), "Just now")
    }

    func testBarIsOneBlockPerHour() {
        func bar(left: TimeInterval) -> Bar {
            Display.widget(event: countdown(to: end), now: end.addingTimeInterval(-left), calendar: cal).bar
        }
        // The Lock Screen screenshot: 6 hr, 16 min is six whole blocks and about a quarter of a seventh.
        let b = bar(left: hms(6, 16))
        XCTAssertEqual(b.unit, .hour)
        XCTAssertEqual(b.full, 6)
        XCTAssertEqual(b.partial, 16.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(b.blocks, 7)

        XCTAssertEqual(bar(left: hms(8)), Bar(unit: .hour, full: 8, partial: 0))
        XCTAssertEqual(bar(left: hms(0, 30)), Bar(unit: .hour, full: 0, partial: 0.5))
        XCTAssertEqual(bar(left: hms(24)), Bar(unit: .hour, full: 24, partial: 0))
        XCTAssertEqual(bar(left: 0), .empty)

        // Past a day each block is a day, counted in the whole hours the words show.
        let d = bar(left: hms(25))
        XCTAssertEqual(d.unit, .day)
        XCTAssertEqual(d.full, 1)
        XCTAssertEqual(d.partial, 1.0 / 24.0, accuracy: 1e-9)

        XCTAssertEqual(Bar.forSpan(seconds: 24 * 86400).unit, .day)
        XCTAssertEqual(Bar.forSpan(seconds: 25 * 86400).unit, .week)
        XCTAssertEqual(Bar.forSpan(seconds: 24 * 7 * 86400 + 1).unit, .month)
        XCTAssertEqual(Bar.forSpan(seconds: 24 * 30 * 86400 + 1).unit, .year)
        XCTAssertEqual(Bar.forSpan(seconds: 90 * 365 * 86400), Bar(unit: .year, full: Bar.maxBlocks, partial: 0))
        for s in [1, 59, 3600, 5000, 86400, 100_000, 5_000_000, 50_000_000, 900_000_000] {
            let x = Bar.forSpan(seconds: s)
            XCTAssertLessThanOrEqual(x.blocks, Bar.maxBlocks)
            XCTAssertGreaterThanOrEqual(x.blocks, 1)
            XCTAssertTrue(x.partial >= 0 && x.partial < 1)
        }
    }

    func testBarFillsUpForTimeSince() {
        let began = at(2026, 11, 19, 9, 0)
        let w = Display.widget(event: since(from: began), now: began.addingTimeInterval(hms(2, 20, 30)), calendar: cal)
        XCTAssertEqual(w.bar.full, 2)
        XCTAssertEqual(w.bar.partial, 20.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(w.state, .running)
        XCTAssertEqual(w.mode, .since)
    }

    func testCards() {
        func card(left: TimeInterval, seconds: Bool) -> CardDisplay {
            Display.card(event: countdown(to: end), now: end.addingTimeInterval(-left), showSeconds: seconds, calendar: cal)
        }
        XCTAssertEqual(card(left: hms(6, 21, 16), seconds: false), CardDisplay(big: "6 hours", detail: "22 mins", state: .running))
        XCTAssertEqual(card(left: hms(6, 21, 16), seconds: true),
                       CardDisplay(big: "6 hours", detail: "21 mins, 16 secs", state: .running))
        XCTAssertEqual(card(left: hms(6 * 24 + 9, 20), seconds: false),
                       CardDisplay(big: "6 days", detail: "9 hrs, 20 mins", state: .running))
        XCTAssertEqual(card(left: hms(1, 0, 0), seconds: false), CardDisplay(big: "1 hour", detail: "", state: .running))
        XCTAssertEqual(card(left: hms(1, 1, 0), seconds: false), CardDisplay(big: "1 hour", detail: "1 min", state: .running))
        XCTAssertEqual(card(left: 45, seconds: false), CardDisplay(big: "1 min", detail: "", state: .running))
        XCTAssertEqual(card(left: 45, seconds: true), CardDisplay(big: "45 secs", detail: "", state: .running))
        XCTAssertEqual(card(left: 0.5, seconds: true), CardDisplay(big: "1 sec", detail: "", state: .running))
        XCTAssertEqual(card(left: 0, seconds: true), CardDisplay(big: "Finished", detail: "", state: .finished))

        let began = at(2026, 11, 19, 9, 0)
        let up = Display.card(event: since(from: began), now: began.addingTimeInterval(hms(2, 20, 30)),
                              showSeconds: true, calendar: cal)
        XCTAssertEqual(up, CardDisplay(big: "2 hours", detail: "20 mins, 30 secs", state: .running))
        let fresh = Display.card(event: since(from: began), now: began.addingTimeInterval(20), showSeconds: false, calendar: cal)
        XCTAssertEqual(fresh, CardDisplay(big: "Just now", detail: "", state: .running))
    }

    /// The card and the widget never disagree about the minutes when seconds are off.
    func testCardAndWidgetAgree() {
        var left = 1.0
        while left < hms(23, 59) {
            let now = end.addingTimeInterval(-left)
            let widget = Display.widget(event: countdown(to: end), now: now, calendar: cal).timeText
            let card = Display.card(event: countdown(to: end), now: now, showSeconds: false, calendar: cal)
            let m = TimeMath.unitsLeft(until: end, now: now, precision: .minutes)
            XCTAssertEqual(widget, Display.compact(TimeMath.split(m, precision: .minutes)))
            let joined = card.detail.isEmpty ? card.big : card.big + ", " + card.detail
            let expected = widget.replacingOccurrences(of: " hr", with: m >= 120 ? " hours" : " hour")
                .replacingOccurrences(of: " min", with: m % 60 == 1 ? " min" : " mins")
            XCTAssertEqual(joined, expected)
            left += 613
        }
    }

    func testAllDayCountdown() {
        let christmas = countdown("Christmas", to: at(2026, 12, 25), allDay: true)
        func show(_ now: Date) -> WidgetDisplay { Display.widget(event: christmas, now: now, calendar: cal) }
        XCTAssertEqual(show(at(2026, 11, 19, 21, 0)).timeText, "36 days")
        XCTAssertEqual(show(at(2026, 12, 23, 0, 0)).timeText, "2 days")
        XCTAssertEqual(show(at(2026, 12, 24, 23, 59)).timeText, "1 day")
        XCTAssertEqual(show(at(2026, 12, 25, 0, 0)).timeText, "Today")
        XCTAssertEqual(show(at(2026, 12, 25, 0, 0)).state, .today)
        XCTAssertEqual(show(at(2026, 12, 25, 23, 59)).state, .today)
        XCTAssertEqual(show(at(2026, 12, 26, 0, 0)).state, .finished)
        XCTAssertFalse(Display.isFinished(christmas, now: at(2026, 12, 25, 23, 59), calendar: cal))
        XCTAssertTrue(Display.isFinished(christmas, now: at(2026, 12, 26, 0, 0), calendar: cal))
        XCTAssertEqual(show(at(2026, 12, 20, 9, 0)).bar, Bar(unit: .day, full: 5, partial: 0))
        XCTAssertEqual(Display.card(event: christmas, now: at(2026, 12, 20, 9, 0), showSeconds: true, calendar: cal),
                       CardDisplay(big: "5 days", detail: "", state: .running))
    }

    func testAllDayTimeSince() {
        let moved = since("Moved in", from: at(2026, 11, 1), allDay: true)
        func show(_ now: Date) -> WidgetDisplay { Display.widget(event: moved, now: now, calendar: cal) }
        XCTAssertEqual(show(at(2026, 11, 1, 15, 0)).timeText, "Today")
        XCTAssertEqual(show(at(2026, 11, 2, 0, 0)).timeText, "1 day")
        XCTAssertEqual(show(at(2026, 11, 19, 21, 0)).timeText, "18 days")
        XCTAssertEqual(show(at(2026, 10, 30, 9, 0)).timeText, "Today")
        XCTAssertFalse(Display.isFinished(moved, now: at(2030, 1, 1), calendar: cal))
    }

    func testFinishedAndReusable() {
        let oneOff = Display.widget(event: countdown(to: end), now: end, calendar: cal)
        XCTAssertEqual(oneOff.state, .finished)
        XCTAssertNil(oneOff.hint)
        XCTAssertEqual(oneOff.bar, .empty)
        let again = Display.widget(event: countdown(to: end, reusable: true, usual: [1020]), now: end, calendar: cal)
        XCTAssertEqual(again.hint, "Tap to set again")
        XCTAssertTrue(Display.isFinished(countdown(to: end), now: end, calendar: cal))
        XCTAssertFalse(Display.isFinished(countdown(to: end), now: end.addingTimeInterval(-0.5), calendar: cal))
        XCTAssertFalse(Display.isFinished(since(from: end), now: end.addingTimeInterval(500), calendar: cal))
    }

    func testSamples() {
        XCTAssertEqual(WidgetDisplay.sample(mode: .countdown).bar.blocks, 7)
        XCTAssertEqual(WidgetDisplay.nothing(mode: .since).state, .empty)
        XCTAssertEqual(Display.compact(Amount()), "")
    }
}
