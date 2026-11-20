// UI tests on the iPhone Simulator: the real app, driven by real taps.
// The clock is pinned and the time zone fixed, so every number on screen is known in advance.

import XCTest

class CurtainUITestCase: XCTestCase {
    /// 2:45:10 PM on Thursday 19 November 2026, Toronto time.
    static let afternoon = "2026-11-19T14:45:10-05:00"

    override func setUp() {
        continueAfterFailure = false
    }

    func launch(seed: String? = nil, now: String = CurtainUITestCase.afternoon, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestNow", now, "-UITestTimeZone", "America/Toronto"] + extra
        if let seed = seed { app.launchArguments += ["-UITestSeed", seed] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Curtain"].waitForExistence(timeout: 20), "the dashboard didn't appear")
        return app
    }

    /// Saves a screenshot next to the repository (CI keeps it with the logs).
    func shot(_ name: String) {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("logs/shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent(name + ".png"))
    }

    /// iOS writes times as "9:00 PM" with a narrow no-break space before PM. For comparing, make
    /// every such space an ordinary one.
    func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func card(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["card." + name]
    }

    /// Waits for a card and returns everything it says, as one line.
    func cardText(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let c = card(app, name)
        XCTAssertTrue(c.waitForExistence(timeout: 10), "no card called \(name)", file: file, line: line)
        return plain(c.label)
    }

    func waitGone(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: element)
        waitForExpectations(timeout: 10) { error in
            if error != nil { XCTFail("\(what) is still there", file: file, line: line) }
        }
    }

    /// A switch in a list row only flips when the switch itself is tapped, not the row.
    func flip(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
}

final class DashboardUITests: CurtainUITestCase {
    func testDashboardShowsEveryKindOfCountdown() {
        let app = launch(seed: "work")
        // 9:00 PM minus 2:45:10 PM is 6:14:50, which rounds up to 6 hours 15 minutes.
        let work = cardText(app, "Done work")
        XCTAssertTrue(work.contains("6 hours"), work)
        XCTAssertTrue(work.contains("15 mins"), work)
        XCTAssertTrue(work.contains("Ends 9:00 PM"), work)
        XCTAssertTrue(cardText(app, "Holiday").contains("35 days"))
        let parcel = cardText(app, "Parcel arrives")
        XCTAssertTrue(parcel.contains("5 days") && parcel.contains("9 hrs, 20 mins"), parcel)
        let phone = cardText(app, "New phone")
        XCTAssertTrue(phone.contains("3 days") && phone.contains("4 hrs, 59 mins"), phone)
        XCTAssertTrue(cardText(app, "Laundry").contains("Finished"))
        print("NOTE dashboard: \(work) | \(parcel) | \(phone)")
        shot("dashboard")
        app.swipeUp()
        shot("dashboard-2")
    }

    /// The reason for the app: set to exactly 7:00 PM, at 6:50 it says 10 minutes, not 9.
    func testTenMinutesAtSixFifty() {
        let app = launch(seed: "seven", now: "2026-11-19T18:50:30-05:00")
        let text = cardText(app, "Done work")
        XCTAssertTrue(text.contains("10 mins"), text)
        XCTAssertFalse(text.contains("9 mins"), text)
        XCTAssertTrue(text.contains("Ends 7:00 PM"), text)
        print("NOTE at 6:50:30 with the end at 7:00: \(text)")
        shot("six-fifty")

        // With seconds switched on the same card counts 9 minutes 30 seconds: also exact.
        app.buttons["toolbar.settings"].tap()
        flip(app.switches["settings.seconds"])
        shot("settings")
        app.buttons["Done"].tap()
        let exact = cardText(app, "Done work")
        XCTAssertTrue(exact.contains("9 mins") && exact.contains("30 secs"), exact)
    }

    func testOneMinuteEitherSideOfTheHour() {
        // 6:59:59 still shows a minute; nothing is ever shown as zero while time remains.
        var app = launch(seed: "seven", now: "2026-11-19T18:59:59-05:00")
        XCTAssertTrue(cardText(app, "Done work").contains("1 min"))
        app.terminate()
        // On the dot of 6:00 with the end at 7:00: exactly one hour, not "59 mins".
        app = launch(seed: "seven", now: "2026-11-19T18:00:00-05:00")
        let text = cardText(app, "Done work")
        XCTAssertTrue(text.contains("1 hour"), text)
        XCTAssertFalse(text.contains("59"), text)
    }

    func testSelectSeveralAndDelete() {
        let app = launch(seed: "work")
        _ = cardText(app, "Laundry")
        app.buttons["toolbar.select"].tap()
        shot("select-empty")
        // One tap picks every ended one-off countdown; the reusable one is left alone.
        app.buttons["select.finished"].tap()
        XCTAssertEqual(app.buttons["select.delete"].label, "Delete (3)")
        // Tap one more by hand, then un-tap it.
        card(app, "Holiday").tap()
        XCTAssertEqual(app.buttons["select.delete"].label, "Delete (4)")
        shot("select")
        card(app, "Holiday").tap()
        XCTAssertEqual(app.buttons["select.delete"].label, "Delete (3)")
        app.buttons["select.delete"].tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("select-confirm")
        confirm.tap()
        waitGone(card(app, "Laundry"), "Laundry")
        XCTAssertFalse(card(app, "Dentist").exists)
        XCTAssertFalse(card(app, "Pizza").exists)
        XCTAssertTrue(card(app, "Done work").exists)
        XCTAssertTrue(card(app, "Holiday").exists)
        XCTAssertTrue(card(app, "New phone").exists)
        XCTAssertTrue(app.buttons["toolbar.select"].exists, "selecting should end after the delete")
        shot("select-after")
    }
}

final class ReusableUITests: CurtainUITestCase {
    func testSetAnEndedCountdownToAUsualTime() {
        let app = launch(seed: "ended")
        let before = cardText(app, "Done work")
        XCTAssertTrue(before.contains("Not running"), before)
        XCTAssertTrue(before.contains("Tap to set again"), before)
        shot("reusable-ended")
        card(app, "Done work").tap()
        let seven = app.buttons["usual.1140"]
        XCTAssertTrue(seven.waitForExistence(timeout: 10))
        let sevenText = plain(seven.label)
        XCTAssertTrue(sevenText.contains("7:00 PM"), sevenText)
        XCTAssertTrue(sevenText.contains("Today"), sevenText)
        XCTAssertTrue(sevenText.contains("in 4 hr, 15 min"), sevenText)
        XCTAssertTrue(plain(app.buttons["usual.1020"].label).contains("5:00 PM"))
        XCTAssertTrue(plain(app.buttons["usual.1260"].label).contains("9:00 PM"))
        shot("reusable-sheet")
        seven.tap()
        waitGone(seven, "the sheet")
        // 7:00 PM minus 2:45:10 PM is 4:14:50: 4 hours 15 minutes.
        let after = cardText(app, "Done work")
        XCTAssertTrue(after.contains("4 hours") && after.contains("15 mins"), after)
        XCTAssertTrue(after.contains("Ends 7:00 PM"), after)
        shot("reusable-set")
    }

    func testAUsualTimeThatHasPassedMeansTomorrow() {
        // At 6:50 PM, 5:00 PM is tomorrow's.
        let app = launch(seed: "ended", now: "2026-11-19T18:50:30-05:00")
        card(app, "Done work").tap()
        let five = app.buttons["usual.1020"]
        XCTAssertTrue(five.waitForExistence(timeout: 10))
        XCTAssertTrue(five.label.contains("Tomorrow"), five.label)
        XCTAssertTrue(app.buttons["usual.1140"].label.contains("Today"))
        five.tap()
        waitGone(five, "the sheet")
        let text = cardText(app, "Done work")
        XCTAssertTrue(text.contains("22 hours") && text.contains("10 mins"), text)
        XCTAssertTrue(text.contains("Ends tomorrow"), text)
    }

    func testStartFromNothingWithDoneWork() {
        let app = launch()
        XCTAssertTrue(app.buttons["empty.donework"].waitForExistence(timeout: 10))
        shot("empty")
        app.buttons["empty.donework"].tap()
        let five = app.buttons["usual.1020"]
        XCTAssertTrue(five.waitForExistence(timeout: 10))
        five.tap()
        waitGone(five, "the sheet")
        // 5:00 PM minus 2:45:10 PM is 2:14:50: 2 hours 15 minutes.
        let text = cardText(app, "Done work")
        XCTAssertTrue(text.contains("2 hours") && text.contains("15 mins"), text)
    }
}

final class EditorUITests: CurtainUITestCase {
    func testNewCountdownStartsAtTheNextHourNotMidnight() {
        let app = launch()
        app.buttons["empty.new"].tap()
        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Flight")
        shot("editor-new")
        app.buttons["editor.save"].tap()
        // Left alone, a new countdown ends at the next full hour: 3:00 PM, 15 minutes away.
        let text = cardText(app, "Flight")
        XCTAssertTrue(text.contains("15 mins"), text)
        XCTAssertTrue(text.contains("Ends 3:00 PM"), text)
    }

    func testTimeSinceStartsNow() {
        let app = launch()
        app.buttons["empty.new"].tap()
        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("New job")
        app.buttons["Time since"].tap()
        app.buttons["editor.save"].tap()
        let text = cardText(app, "New job")
        XCTAssertTrue(text.contains("Just now"), text)
        XCTAssertTrue(text.contains("Since 2:45 PM"), text)
    }

    func testEditingAReusableCountdown() {
        let app = launch(seed: "work")
        card(app, "Done work").tap()
        XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 10))
        shot("detail")
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 10))
        shot("editor-reusable")
        app.swipeUp()
        // Its usual times are listed, each with a remove button.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '7:00'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '9:00'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove 7:00'")).firstMatch.exists)
        shot("editor-reusable-2")
    }
}

final class FlowUITests: CurtainUITestCase {
    /// Tapping a widget opens curtain://event/<id>; the app goes straight to that countdown.
    func testWidgetTapOpensItsCountdown() {
        let app = launch(seed: "ended")
        _ = cardText(app, "Done work")
        XCUIDevice.shared.system.open(URL(string: "curtain://event/D0E0D0E0-0000-4000-8000-000000000001")!)
        // Two taps from the widget to a running countdown: the widget, then the time.
        let nine = app.buttons["usual.1260"]
        XCTAssertTrue(nine.waitForExistence(timeout: 15), "the countdown's sheet didn't open")
        nine.tap()
        waitGone(nine, "the sheet")
        XCTAssertTrue(cardText(app, "Done work").contains("Ends 9:00 PM"))
        // A link to something that doesn't exist does nothing.
        XCUIDevice.shared.system.open(URL(string: "curtain://event/00000000-0000-4000-8000-000000000000")!)
        sleep(2)
        XCTAssertFalse(app.buttons["detail.edit"].exists)
        XCTAssertTrue(card(app, "Done work").exists)
    }

    func testCountdownsAreStillThereAfterQuitting() {
        var app = launch(seed: "work")
        _ = cardText(app, "Holiday")
        app.terminate()
        // No reset and no seed this time: only what was saved.
        app = XCUIApplication()
        app.launchArguments = ["-UITestNow", CurtainUITestCase.afternoon, "-UITestTimeZone", "America/Toronto"]
        app.launch()
        XCTAssertTrue(cardText(app, "Done work").contains("6 hours"))
        XCTAssertTrue(cardText(app, "Holiday").contains("35 days"))
        XCTAssertTrue(card(app, "Pizza").exists)
    }

    func testADamagedFileIsSetAsideNotOverwritten() {
        let app = launch(extra: ["-UITestDamagedFile"])
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'set aside as state-unreadable-'")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "no word about the damaged file")
        print("NOTE damaged file: \(notice.label)")
        shot("damaged-file")
        // The app still works.
        app.buttons["empty.donework"].tap()
        let five = app.buttons["usual.1020"]
        XCTAssertTrue(five.waitForExistence(timeout: 10))
        five.tap()
        waitGone(five, "the sheet")
        XCTAssertTrue(cardText(app, "Done work").contains("2 hours"))
    }

    func testMakeACountdownReusableAndRestartATimeSince() {
        let app = launch(seed: "work")
        // "Parcel arrives" is a one-off. Make it reusable with a usual time of 5:00 PM.
        card(app, "Parcel arrives").tap()
        XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["usual.1020"].exists)
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 10))
        app.swipeUp()
        flip(app.switches["editor.reusable"])
        let add = app.buttons["editor.addusual"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        shot("editor-made-reusable")
        app.buttons["editor.save"].tap()
        let text = cardText(app, "Parcel arrives")
        XCTAssertTrue(text.contains("Reusable"), text)
        card(app, "Parcel arrives").tap()
        let five = app.buttons["usual.1020"]
        XCTAssertTrue(five.waitForExistence(timeout: 10), "the usual time wasn't saved")
        app.buttons["Close"].tap()
        waitGone(five, "the sheet")

        // "New phone" has been counting for three days. Start it again from now.
        card(app, "New phone").tap()
        let restart = app.buttons["detail.restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: 10))
        restart.tap()
        let confirm = app.buttons["Start again"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        app.buttons["Close"].tap()
        waitGone(restart, "the sheet")
        let phone = cardText(app, "New phone")
        XCTAssertTrue(phone.contains("Just now"), phone)
        XCTAssertTrue(phone.contains("Since 2:45 PM"), phone)
    }

    func testDeleteFromTheDetailSheet() {
        let app = launch(seed: "work")
        card(app, "Dentist").tap()
        let delete = app.buttons["detail.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        // The row and the confirmation are both called Delete; the confirmation is the newer one.
        let buttons = app.buttons.matching(NSPredicate(format: "label == 'Delete'"))
        XCTAssertTrue(buttons.element(boundBy: 1).waitForExistence(timeout: 5), "no confirmation")
        buttons.element(boundBy: buttons.count - 1).tap()
        waitGone(card(app, "Dentist"), "Dentist")
        XCTAssertTrue(card(app, "Done work").exists)
    }
}

final class ColourUITests: CurtainUITestCase {
    func testPickAThemeAndMatchAWallpaper() {
        let app = launch(seed: "seven", extra: ["-UITestWallpaper"])
        card(app, "Done work").tap()
        XCTAssertTrue(app.buttons["detail.edit"].waitForExistence(timeout: 10))
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 10))
        app.swipeUp()
        app.buttons["editor.colours"].tap()
        let ocean = app.buttons["theme.Ocean"]
        XCTAssertTrue(ocean.waitForExistence(timeout: 10))
        ocean.tap()
        shot("colours")
        app.swipeUp()
        shot("colours-2")
        app.buttons["theme.wallpaper"].tap()
        let choose = app.buttons["wallpaper.choose"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()
        let first = app.buttons["wallpaper.set.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "no colour sets came out of the picture")
        XCTAssertTrue(app.buttons["wallpaper.swatch.0"].exists)
        first.tap()
        shot("wallpaper")
        app.swipeUp()
        shot("wallpaper-2")
        app.buttons["wallpaper.keep"].tap()
        // Back to the editor and save.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["theme.Ocean"].waitForExistence(timeout: 10) || app.buttons["theme.wallpaper"].exists)
        app.swipeDown()
        XCTAssertTrue(app.buttons["theme.From wallpaper"].waitForExistence(timeout: 10), "the kept set isn't listed")
        shot("colours-kept")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 10))
        app.buttons["editor.save"].tap()
        _ = cardText(app, "Done work")
        shot("dashboard-wallpaper-colours")
    }
}

final class WidgetGalleryUITests: CurtainUITestCase {
    func testSeeTheWidgets() {
        let app = launch(seed: "work")
        app.buttons["toolbar.settings"].tap()
        let gallery = app.buttons["settings.gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        let status = app.descendants(matching: .any).matching(identifier: "settings.widgetstatus").firstMatch
        print("NOTE widget status: \(status.exists ? status.label : "(not shown)")")
        gallery.tap()
        XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 10))
        shot("widgets")
        app.swipeUp()
        shot("widgets-2")
        app.swipeUp()
        shot("widgets-3")
    }
}
