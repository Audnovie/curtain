// Writes down what iOS's own self-updating clock text says on this version of iOS, and takes a
// picture of the widget faces with that text in them. Nothing here can fail the build except
// the probe screen not appearing; the notes are read by a person.

import XCTest

final class ProbeUITests: CurtainUITestCase {
    func testWhatTheSystemClockTextSays() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestProbe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["probe.ready"].waitForExistence(timeout: 20))
        // One look at the whole screen, so nothing ticks over halfway through reading it.
        let tree = app.debugDescription
        for line in tree.components(separatedBy: "\n") where line.contains("identifier: 'probe.") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if let cut = text.range(of: "identifier: ") {
                print("NOTE PROBE \(plain(String(text[cut.lowerBound...])))")
            }
        }
        shot("probe-1")
        app.swipeUp()
        shot("probe-2")
        app.swipeUp()
        shot("probe-3")
    }
}
