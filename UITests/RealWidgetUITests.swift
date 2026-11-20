// The real widget extension, placed on the simulator's Home Screen by driving iOS itself.
// This is the only test that runs the widget the way a phone would: as its own program, reading
// the app's saved file from the folder the two share. It runs as a separate, best-effort CI step
// (TEST_RUNNER_CURTAIN_REAL_WIDGET=1), because it depends on how this iOS version lays out its
// Home Screen editing, which Apple changes.

import XCTest

final class RealWidgetUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var step = 0

    private var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("logs/real", isDirectory: true)
    }

    private func note(_ text: String) {
        print("NOTE REAL \(text)")
    }

    /// A screenshot and, when asked, everything iOS says is on screen (to adapt this test from).
    private func record(_ name: String, tree: Bool = false) {
        step += 1
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let base = String(format: "%02d-%@", step, name)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: logs.appendingPathComponent(base + ".png"))
        if tree {
            try? springboard.debugDescription.write(to: logs.appendingPathComponent(base + ".txt"), atomically: true, encoding: .utf8)
        }
    }

    /// The first of several ways to name the same control that exists.
    private func find(_ candidates: [XCUIElement], timeout: TimeInterval = 6) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for c in candidates where c.exists && c.isHittable { return c }
            usleep(300_000)
        } while Date() < end
        return nil
    }

    /// The note the widget extension writes each time iOS asks it for a timeline.
    private func widgetNote() -> String? {
        // The test runner lives at <device>/data/Containers/Data/Application/<id>; the shared
        // folder is under <device>/data/Containers/Shared/AppGroup.
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let data = home.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let groups = data.appendingPathComponent("Shared/AppGroup")
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: groups.path) else { return nil }
        for id in ids {
            let file = groups.appendingPathComponent(id).appendingPathComponent("Library/Application Support/Curtain/widget-seen.json")
            if let text = try? String(contentsOf: file, encoding: .utf8) { return text }
        }
        return nil
    }

    func testWidgetOnTheHomeScreen() throws {
        guard ProcessInfo.processInfo.environment["CURTAIN_REAL_WIDGET"] == "1" else {
            throw XCTSkip("runs only in its own CI step")
        }
        continueAfterFailure = true

        // 1. Open the app once with real time, so there is a saved countdown to show.
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestSeed", "work"]
        app.launch()
        XCTAssertTrue(app.buttons["card.Done work"].waitForExistence(timeout: 20))
        note("app says: \(app.buttons["card.Done work"].label)")
        XCTAssertNil(widgetNote(), "a widget note exists before any widget was added")

        // 2. Home Screen, then its editing mode.
        XCUIDevice.shared.press(.home)
        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(1)
        record("home", tree: true)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 2.0)
        sleep(1)
        record("after-long-press", tree: true)
        if let editHome = find([springboard.buttons["Edit Home Screen"]], timeout: 2) {
            editHome.tap()
            sleep(1)
        }
        guard let edit = find([springboard.buttons["Edit"], springboard.buttons["Add"],
                               springboard.buttons["Add Widget"]]) else {
            record("no-edit-button", tree: true)
            return XCTFail("couldn't get the Home Screen into editing mode")
        }
        note("tapping \(edit.label)")
        edit.tap()
        sleep(1)
        record("edit-menu", tree: true)
        if let add = find([springboard.buttons["Add Widget"], springboard.staticTexts["Add Widget"],
                           springboard.collectionViews.buttons["Add Widget"]], timeout: 4) {
            add.tap()
            sleep(2)
        }
        record("gallery", tree: true)

        // 3. Find Curtain in the widget gallery.
        if let search = find([springboard.searchFields.firstMatch, springboard.textFields.firstMatch], timeout: 5) {
            search.tap()
            search.typeText("Curtain")
            sleep(2)
        }
        record("search", tree: true)
        guard let row = find([springboard.collectionViews.cells["Curtain"],
                              springboard.cells["Curtain"],
                              springboard.collectionViews.staticTexts["Curtain"],
                              springboard.staticTexts["Curtain"],
                              springboard.buttons["Curtain"]], timeout: 8) else {
            record("not-in-gallery", tree: true)
            return XCTFail("Curtain isn't in the widget gallery")
        }
        note("found Curtain in the gallery")
        row.tap()
        sleep(2)
        record("curtain-widgets", tree: true)

        // 4. Add the first one offered (the small "Time left").
        guard let addButton = find([springboard.buttons["Add Widget"], springboard.buttons[" Add Widget"],
                                    springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch],
                                   timeout: 8) else {
            record("no-add-button", tree: true)
            return XCTFail("no Add Widget button")
        }
        addButton.tap()
        sleep(3)
        record("added", tree: true)
        if let done = find([springboard.buttons["Done"]], timeout: 5) {
            done.tap()
        } else {
            XCUIDevice.shared.press(.home)
        }
        sleep(4)
        record("home-with-widget", tree: true)

        // 5. The widget ran as its own program and could read the app's file.
        var seen: String?
        for _ in 0..<20 {
            seen = widgetNote()
            if seen != nil { break }
            sleep(1)
        }
        note("widget note: \(seen ?? "none")")
        XCTAssertNotNil(seen, "the widget never asked for data")
        XCTAssertTrue(seen?.contains("\"kind\":\"countdown\"") ?? false, seen ?? "")
        XCTAssertTrue(seen?.contains("\"events\":7") ?? false, "the widget couldn't read the app's countdowns: \(seen ?? "")")
        let texts = springboard.staticTexts.allElementsBoundByIndex.map { $0.label }.filter { !$0.isEmpty }
        note("home screen texts: \(texts.joined(separator: " | "))")
        let widgets = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Done work'"))
        note("elements mentioning Done work: \(widgets.count)")
        for i in 0..<min(widgets.count, 4) {
            note("  \(widgets.element(boundBy: i).elementType.rawValue): \(widgets.element(boundBy: i).label)")
        }
        XCTAssertGreaterThan(widgets.count, 0, "nothing on the Home Screen shows the countdown")

        // 6. The app can tell too.
        app.activate()
        app.buttons["toolbar.settings"].tap()
        let status = app.descendants(matching: .any).matching(identifier: "settings.widgetstatus").firstMatch
        if status.waitForExistence(timeout: 10) {
            note("app's widget status: \(status.label)")
        }
        record("app-settings")
    }
}
