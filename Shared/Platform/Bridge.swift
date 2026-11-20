// Small bridges between the plain model and SwiftUI, used by the app and by the widgets.

import SwiftUI
import CurtainCore

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

extension Theme {
    /// The card background: a top-to-bottom blend, or a flat colour.
    var fill: LinearGradient {
        LinearGradient(colors: [background.color, (background2 ?? background).color],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension WidgetDisplay {
    /// "6 hr, 16 min" split for a two-line layout: "6 hr" and "16 min".
    var primaryText: String {
        timeText.components(separatedBy: ", ").first ?? timeText
    }

    var secondaryText: String {
        let parts = timeText.components(separatedBy: ", ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: ", ") : ""
    }
}

/// The clock the app reads. UI tests can pin it and choose the time zone, so that screenshots
/// and checks come out the same on every run:
///     -UITestNow 2026-11-19T18:50:30-05:00  -UITestTimeZone America/Toronto
/// Widgets always use the real clock.
enum AppClock {
    #if DEBUG
    static let arguments = ProcessInfo.processInfo.arguments
    #else
    /// A build made for a phone ignores every test switch (-UITestReset and the rest).
    static let arguments: [String] = []
    #endif

    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static let pinned: Date? = {
        guard let text = value(after: "-UITestNow") else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }()

    static let timeZone: TimeZone = {
        if let id = value(after: "-UITestTimeZone"), let tz = TimeZone(identifier: id) { return tz }
        return TimeZone.autoupdatingCurrent
    }()

    static var calendar: Calendar {
        var c = Calendar.autoupdatingCurrent
        c.timeZone = timeZone
        return c
    }

    static var now: Date { pinned ?? Date() }

    /// The moment to draw for a view refreshed on a schedule. Never earlier than the scheduled
    /// moment itself, so a tick that fires a hair early can't show the previous minute.
    static func now(scheduled: Date) -> Date {
        pinned ?? max(Date(), scheduled)
    }
}
