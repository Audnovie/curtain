// The real widgets, placed on the simulator's Home Screen and Lock Screen by driving iOS itself.
// These are the only tests that run a widget the way a phone would: as its own program, reading
// the app's saved file from the folder the two share. They run as a separate, best-effort CI
// step (TEST_RUNNER_CURTAIN_REAL_WIDGET=1), because they depend on how this version of iOS lays
// out its editing screens, which Apple changes.

import XCTest

final class RealWidgetUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var step = 0
    private var prefix = "home"

    private var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("logs/real", isDirectory: true)
    }

    private func note(_ text: String) {
        print("NOTE REAL \(text)")
    }

    /// A screenshot and everything iOS says is on screen (to adapt this test from). Returns the
    /// description of the screen, read once so that nothing moves while it is being looked at.
    @discardableResult
    private func record(_ name: String) -> String {
        step += 1
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let base = String(format: "%@-%02d-%@", prefix, step, name)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: logs.appendingPathComponent(base + ".png"))
        let tree = springboard.debugDescription
        try? tree.write(to: logs.appendingPathComponent(base + ".txt"), atomically: true, encoding: .utf8)
        return tree
    }

    /// The first of several ways to name the same control that is on screen and can be tapped.
    private func find(_ candidates: [XCUIElement], timeout: TimeInterval = 6) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for c in candidates where c.exists && c.isHittable { return c }
            usleep(300_000)
        } while Date() < end
        return nil
    }

    private func labelled(_ text: String) -> [XCUIElement] {
        [springboard.buttons[text], springboard.staticTexts[text], springboard.cells[text],
         springboard.otherElements[text],
         springboard.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch]
    }

    /// The note the widget extension writes each time iOS asks it for a timeline.
    private func widgetNote() -> String? {
        // The test runner lives at <device>/data/Containers/Data/Application/<id>; the shared
        // folder is under <device>/data/Containers/Shared/AppGroup.
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let containers = home.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let groups = containers.appendingPathComponent("Shared/AppGroup")
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: groups.path) else { return nil }
        for id in ids {
            let file = groups.appendingPathComponent(id)
                .appendingPathComponent("Library/Application Support/Curtain/widget-seen.json")
            if let text = try? String(contentsOf: file, encoding: .utf8) { return text }
        }
        return nil
    }

    private func waitForNote(containing text: String, seconds: Int = 25) -> String? {
        var seen: String?
        for _ in 0..<seconds {
            seen = widgetNote()
            if let s = seen, s.contains(text) { return s }
            sleep(1)
        }
        return seen
    }

    /// Opens the app once with the real clock, so there is a saved file for a widget to read.
    private func seedTheApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestSeed", "work"]
        app.launch()
        XCTAssertTrue(app.buttons["card.Done work"].waitForExistence(timeout: 20))
        note("app says: \(app.buttons["card.Done work"].label) | \(app.buttons["card.New phone"].label)")
        return app
    }

    private func goHome() {
        XCUIDevice.shared.press(.home)
        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(1)
    }

    func testWidgetOnTheHomeScreen() throws {
        guard ProcessInfo.processInfo.environment["CURTAIN_REAL_WIDGET"] == "1" else {
            throw XCTSkip("runs only in its own CI step")
        }
        prefix = "home"
        continueAfterFailure = true
        let app = seedTheApp()
        XCTAssertNil(widgetNote(), "a widget note exists before any widget was added")

        // Home Screen, then its editing mode.
        goHome()
        record("start")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 2.0)
        sleep(1)
        if let editHome = find([springboard.buttons["Edit Home Screen"]], timeout: 2) {
            editHome.tap()
            sleep(1)
        }
        guard let edit = find([springboard.buttons["Edit"]]) else {
            record("no-edit-button")
            return XCTFail("couldn't get the Home Screen into editing mode")
        }
        edit.tap()
        sleep(1)
        guard let add = find(labelled("Add Widget"), timeout: 5) else {
            record("no-add-widget")
            return XCTFail("no Add Widget in the Edit menu")
        }
        add.tap()
        sleep(2)

        // Find Curtain in the widget gallery.
        if let search = find([springboard.searchFields.firstMatch, springboard.textFields.firstMatch], timeout: 5) {
            search.tap()
            search.typeText("Curtain")
            sleep(2)
        }
        guard let row = find(labelled("Curtain"), timeout: 8) else {
            record("not-in-gallery")
            return XCTFail("Curtain isn't in the widget gallery")
        }
        row.tap()
        sleep(3)
        let offered = record("gallery")
        XCTAssertTrue(offered.contains("Time left"), "the gallery doesn't name the widget")

        // Add the first one offered: the small "Time left".
        guard let addButton = find([springboard.buttons["Add Widget"],
                                    springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch],
                                   timeout: 8) else {
            record("no-add-button")
            return XCTFail("no Add Widget button")
        }
        addButton.tap()
        sleep(3)
        if let done = find([springboard.buttons["Done"]], timeout: 5) {
            done.tap()
        } else {
            XCUIDevice.shared.press(.home)
        }
        sleep(4)

        // The widget ran as its own program and could read the app's file.
        let seen = waitForNote(containing: "systemSmall")
        note("widget note: \(seen ?? "none")")
        XCTAssertNotNil(seen, "the widget never asked for data")
        XCTAssertTrue(seen?.contains("\"kind\":\"countdown\"") ?? false, seen ?? "")
        XCTAssertTrue(seen?.contains("\"events\":7") ?? false, "the widget couldn't read the app's countdowns: \(seen ?? "")")

        // And it is on the Home Screen, showing the countdown the app shows.
        let screen = record("with-widget")
        let line = screen.components(separatedBy: "\n").first { $0.contains("label: 'Done work, ") } ?? ""
        note("on the Home Screen: \(line.trimmingCharacters(in: .whitespaces))")
        XCTAssertTrue(screen.contains("identifier: 'Curtain', label: 'Curtain', value: Widget"), "no Curtain widget on the Home Screen")
        XCTAssertTrue(line.contains(" hr"), "the widget isn't showing the countdown")

        // The app can tell a widget has been reading its data.
        app.activate()
        app.buttons["toolbar.settings"].tap()
        let status = app.descendants(matching: .any).matching(identifier: "settings.widgetstatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        note("app's widget status: \(status.label)")
        XCTAssertTrue(status.label.contains("A widget last updated"), status.label)
        XCTAssertFalse(status.label.contains("Not yet"), status.label)
        step += 1
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: logs.appendingPathComponent("home-app-settings.png"))
    }

    /// The widget this app was made for: the block under the Lock Screen clock.
    func testWidgetOnTheLockScreen() throws {
        guard ProcessInfo.processInfo.environment["CURTAIN_REAL_WIDGET"] == "1" else {
            throw XCTSkip("runs only in its own CI step")
        }
        prefix = "lock"
        continueAfterFailure = true
        _ = seedTheApp()
        goHome()

        // Pull the Lock Screen down over the Home Screen, then touch and hold it to customize.
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.0))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8))
        top.press(forDuration: 0.1, thenDragTo: middle)
        sleep(2)
        record("cover-sheet")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 2.5)
        sleep(2)
        record("after-hold")
        guard let customize = find(labelled("Customize"), timeout: 6) else {
            record("no-customize")
            return XCTFail("the Lock Screen didn't offer Customize")
        }
        customize.tap()
        sleep(2)
        record("customize")
        // Older versions ask which of the two screens to change.
        if let lockChoice = find(labelled("Lock Screen"), timeout: 3) {
            lockChoice.tap()
            sleep(2)
            record("chose-lock-screen")
        }
        guard let addWidgets = find(labelled("Add Widgets") + labelled("ADD WIDGETS") + labelled("Widgets"), timeout: 6) else {
            record("no-add-widgets")
            return XCTFail("no widget row to tap on the Lock Screen")
        }
        addWidgets.tap()
        sleep(2)
        record("picker")
        guard let row = find(labelled("Curtain"), timeout: 6) else {
            record("not-in-picker")
            return XCTFail("Curtain isn't in the Lock Screen widget picker")
        }
        row.tap()
        sleep(2)
        let offered = record("curtain-widgets")
        note("picker mentions Time left: \(offered.contains("Time left"))")
        // Tap the first widget offered to add it.
        let candidates = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Time left' OR label CONTAINS[c] 'Done work'"))
        if candidates.count > 0, candidates.firstMatch.isHittable {
            candidates.firstMatch.tap()
        } else {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.75)).tap()
        }
        sleep(3)
        record("after-adding")
        if let close = find(labelled("Close") + labelled("close"), timeout: 3) {
            close.tap()
            sleep(1)
        }
        if let done = find(labelled("Done"), timeout: 5) {
            done.tap()
            sleep(2)
        }
        record("after-done")
        // Tap once more to leave the wallpaper gallery, if it is still up.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        sleep(3)
        let screen = record("lock-screen")
        let seen = waitForNote(containing: "accessory", seconds: 20)
        note("widget note: \(seen ?? "none")")
        XCTAssertTrue(seen?.contains("accessoryRectangular") ?? false, "no Lock Screen widget asked for data: \(seen ?? "none")")
        let line = screen.components(separatedBy: "\n").first { $0.localizedCaseInsensitiveContains("done work") } ?? ""
        note("on the Lock Screen: \(line.trimmingCharacters(in: .whitespaces))")
        XCTAssertFalse(line.isEmpty, "the Lock Screen isn't showing the countdown")
    }
}
