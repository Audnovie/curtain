// The app's copy of the saved file. Every change goes through `update`, which saves it and
// tells the widgets to redraw.

import SwiftUI
import WidgetKit
import CurtainCore

@MainActor
final class Store: ObservableObject {
    @Published private(set) var state: AppState
    /// Something the person should know: a damaged file was set aside, or a save failed.
    @Published var notice: String?
    /// A countdown to open, asked for by tapping a widget.
    @Published var openRequest: UUID?

    let location: SharedContainer.Location
    /// False when a file is there that couldn't be read or moved: saving would destroy it.
    private var canSave = true

    init(location: SharedContainer.Location = SharedContainer.location) {
        self.location = location
        if AppClock.arguments.contains("-UITestReset") {
            try? FileManager.default.removeItem(at: location.file)
            try? FileManager.default.removeItem(at: location.widgetNote)
        }
        var loaded = AppState()
        var message: String?
        var saving = true
        switch StateFile.load(from: location.file) {
        case .loaded(let saved):
            loaded = saved
        case .missing:
            break
        case .unreadable(let why):
            // Never write over a file that couldn't be read. Set it aside instead.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = location.folder.appendingPathComponent("state-unreadable-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: location.file, to: aside)
                message = "Your saved countdowns couldn't be read, so they were set aside as \(aside.lastPathComponent) and the app started fresh. (\(why))"
            } catch {
                saving = false
                message = "Your saved countdowns couldn't be read. Nothing will be saved this time, so that file isn't overwritten. (\(why))"
            }
        }
        state = loaded
        notice = message
        canSave = saving
        if let seed = AppClock.value(after: "-UITestSeed") {
            state = Store.seed(seed, now: AppClock.now, calendar: AppClock.calendar)
            save()
        }
    }

    /// Changes the state, saves it, and has the widgets redraw.
    func update(_ change: (inout AppState) -> Void) {
        var copy = state
        change(&copy)
        guard copy != state else { return }
        state = copy
        save()
    }

    private func save() {
        if canSave {
            do {
                try StateFile.save(state, to: location.file)
            } catch {
                notice = "Couldn't save your countdowns: \(error.localizedDescription)"
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Handles curtain://event/<id>, which is what a widget opens when tapped.
    func open(_ url: URL) {
        guard url.scheme == "curtain", url.host == "event",
              let id = UUID(uuidString: url.lastPathComponent), state.event(id: id) != nil else { return }
        openRequest = id
    }

    // MARK: Starting points for the UI tests

    static func seed(_ name: String, now: Date, calendar: Calendar) -> AppState {
        var s = AppState()
        func add(_ e: Event) { s.upsert(e, now: now, calendar: calendar) }
        let day = 86400.0
        let made = now.addingTimeInterval(-20 * day)
        let work = Event(name: "Done work", mode: .countdown,
                         date: Schedule.next(minuteOfDay: 21 * 60, after: now, calendar: calendar),
                         reusable: true, usualTimes: [17 * 60, 19 * 60, 21 * 60], theme: .ember, createdAt: made)
        switch name {
        case "work":
            add(work)
            add(Event(name: "Holiday", mode: .countdown, date: now.addingTimeInterval(35 * day), allDay: true,
                      theme: .ocean, createdAt: made))
            add(Event(name: "Parcel arrives", mode: .countdown, date: now.addingTimeInterval(5 * day + 9 * 3600 + 20 * 60),
                      theme: .grape, createdAt: made))
            add(Event(name: "New phone", mode: .since, date: now.addingTimeInterval(-(3 * day + 4 * 3600 + 59 * 60)),
                      theme: .forest, createdAt: made))
            add(Event(name: "Laundry", mode: .countdown, date: now.addingTimeInterval(-40 * 60), theme: .slate, createdAt: made))
            add(Event(name: "Dentist", mode: .countdown, date: now.addingTimeInterval(-2 * day), theme: .lagoon, createdAt: made))
            add(Event(name: "Pizza", mode: .countdown, date: now.addingTimeInterval(-5 * day), theme: .sunset, createdAt: made))
        case "ended":
            var ended = work
            ended.date = now.addingTimeInterval(-25 * 60)
            add(ended)
        case "seven":
            // The case from the request: a countdown to exactly 7:00 PM.
            var seven = work
            seven.date = Schedule.next(minuteOfDay: 19 * 60, after: now, calendar: calendar)
            add(seven)
        default:
            break
        }
        return s
    }
}
