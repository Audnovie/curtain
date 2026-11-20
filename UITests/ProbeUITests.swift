import XCTest

final class ProbeUITests: XCTestCase {
    /// Saves a screenshot next to the repository (CI keeps it with the logs).
    private func shot(_ name: String) {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("logs/shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent(name + ".png"))
    }

    func testProbe() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["probe.shared"].waitForExistence(timeout: 15))
        sleep(2)
        print("PROBE \(app.staticTexts["probe.shared"].label)")
        print("PROBE \(app.staticTexts["probe.save"].label)")
        for t in app.staticTexts.allElementsBoundByIndex where t.identifier.hasPrefix("probe.rel.") {
            print("PROBE relative [\(t.identifier)] = [\(t.label)]")
        }
        shot("probe")
        app.swipeUp()
        shot("probe-2")
    }
}
