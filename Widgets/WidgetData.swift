// How the widgets get their data: they read the app's saved file and plan what to show.

import Foundation
import WidgetKit
import CurtainCore

struct CurtainEntry: TimelineEntry {
    let date: Date
    let display: WidgetDisplay
    let theme: Theme
    /// See `PlanEntry.liveReference`.
    let live: Date?
    /// "Ends 9:00 PM". Shown on the medium Home Screen widget.
    let caption: String?
    let eventID: UUID?

    static func sample(_ mode: EventMode) -> CurtainEntry {
        CurtainEntry(date: Date(), display: .sample(mode: mode), theme: mode == .countdown ? .ember : .ocean,
                     live: nil, caption: nil, eventID: nil)
    }
}

enum WidgetData {
    static var calendar: Calendar { Calendar.autoupdatingCurrent }

    static func load() -> AppState? {
        if case .loaded(let state) = StateFile.load(from: SharedContainer.location.file) { return state }
        return nil
    }

    /// The countdown a widget shows: the one picked for it, or the first of its kind if none was
    /// picked or the picked one has been deleted.
    static func event(mode: EventMode, chosen: String?, in state: AppState, now: Date) -> Event? {
        if let text = chosen, let id = UUID(uuidString: text), let e = state.event(id: id), e.mode == mode {
            return e
        }
        return state.defaultEvent(mode: mode, now: now, calendar: calendar)
    }

    static func caption(for event: Event) -> String {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        if event.allDay {
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return (event.mode == .countdown ? "On " : "Since ") + f.string(from: event.moment(calendar: calendar))
        }
        f.dateStyle = .none
        f.timeStyle = .short
        let time = f.string(from: event.date)
        if calendar.isDateInToday(event.date) {
            return (event.mode == .countdown ? "Ends " : "Since ") + time
        }
        let d = DateFormatter()
        d.locale = Locale.autoupdatingCurrent
        d.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return (event.mode == .countdown ? "Ends " : "Since ") + d.string(from: event.date) + ", " + time
    }

    static func entries(mode: EventMode, chosen: String?, now: Date) -> (entries: [CurtainEntry], reloadAfter: Date?) {
        guard let state = load() else {
            // No file to read: the app hasn't been opened yet, or the two can't share a folder.
            let entry = CurtainEntry(date: now, display: .nothing(mode: mode), theme: .ember, live: nil,
                                     caption: nil, eventID: nil)
            return ([entry], now.addingTimeInterval(3600))
        }
        let event = self.event(mode: mode, chosen: chosen, in: state, now: now)
        let plan = TimelineBuilder.plan(event: event, mode: mode, now: now, calendar: calendar)
        let theme = event?.theme ?? state.settings.defaultTheme
        let caption = event.map { self.caption(for: $0) }
        let entries = plan.entries.map {
            CurtainEntry(date: $0.date, display: $0.display, theme: theme, live: $0.liveReference,
                         caption: $0.display.state == .running ? caption : nil, eventID: event?.id)
        }
        var reload = plan.reloadAfter
        // A widget left on "whichever comes first" moves on to the next countdown when this
        // one ends, so it needs one more look just after that.
        let picked = chosen.flatMap { UUID(uuidString: $0) }.flatMap { state.event(id: $0) }
        let leftOnFirst = picked == nil || picked?.id != event?.id
        if reload == nil, leftOnFirst, let last = plan.entries.last, last.display.state == .finished, last.date > now {
            reload = last.date.addingTimeInterval(60)
        }
        return (entries, reload)
    }

    static func timeline(mode: EventMode, chosen: String?, family: WidgetFamily) -> Timeline<CurtainEntry> {
        let now = Date()
        let result = entries(mode: mode, chosen: chosen, now: now)
        WidgetNote(at: now, kind: mode.rawValue, family: String(describing: family), events: load()?.events.count ?? -1)
            .write(to: SharedContainer.location)
        if let reload = result.reloadAfter {
            return Timeline(entries: result.entries, policy: .after(reload))
        }
        return Timeline(entries: result.entries, policy: .never)
    }

    /// Countdowns of one kind, in dashboard order, for the "choose" list when editing a widget.
    static func choices(mode: EventMode) -> [Event] {
        guard let state = load() else { return [] }
        return state.dashboardOrder(now: Date(), calendar: calendar).filter { $0.mode == mode }
    }
}
