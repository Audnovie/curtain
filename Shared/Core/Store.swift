// The saved file, and every change the app can make to it.
// One JSON file holds everything. The app writes it; the widgets only read it.

import Foundation

public enum LoadResult: Equatable, Sendable {
    case loaded(AppState)
    /// No file yet: a first run.
    case missing
    /// A file is there but can't be used. The text says why.
    case unreadable(String)
}

public enum StateFile {
    public static let fileName = "state.json"

    public static func encode(_ state: AppState) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(state)
    }

    public static func decode(_ data: Data) throws -> AppState {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(AppState.self, from: data)
    }

    public static func load(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let state = try decode(try Data(contentsOf: url))
            if state.version > AppState.currentVersion {
                return .unreadable("saved by a newer version of the app (format \(state.version))")
            }
            return .loaded(state)
        } catch {
            return .unreadable(String(describing: error))
        }
    }

    public static func save(_ state: AppState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encode(state).write(to: url, options: .atomic)
    }
}

extension AppState {
    /// Adds a new countdown or replaces the one with the same id.
    public mutating func upsert(_ event: Event, now: Date, calendar: Calendar) {
        var e = event.normalized(calendar: calendar)
        e.updatedAt = now
        if let i = events.firstIndex(where: { $0.id == e.id }) {
            e.createdAt = events[i].createdAt
            events[i] = e
        } else {
            events.append(e)
        }
    }

    public mutating func delete(ids: Set<UUID>) {
        events.removeAll { ids.contains($0.id) }
    }

    /// Points a countdown at a new end. With `remember`, that time of day joins its usual times.
    /// Returns false if there is no such countdown.
    @discardableResult
    public mutating func setCountdown(id: UUID, to date: Date, remember: Bool, now: Date, calendar: Calendar) -> Bool {
        guard let i = events.firstIndex(where: { $0.id == id }), events[i].mode == .countdown else { return false }
        events[i].allDay = false
        events[i].date = Schedule.wholeMinute(date)
        if remember {
            events[i].reusable = true
            let minute = Schedule.minuteOfDay(of: date, calendar: calendar)
            // The newest choice is kept even when the list is full.
            let others = events[i].usualTimes.filter { $0 != minute }
            events[i].usualTimes = Schedule.tidy(usualTimes: Array(others.suffix(Event.maxUsualTimes - 1)) + [minute])
        }
        events[i].updatedAt = now
        return true
    }

    /// Restarts a "time since" from `date`.
    @discardableResult
    public mutating func restartSince(id: UUID, from date: Date, now: Date) -> Bool {
        guard let i = events.firstIndex(where: { $0.id == id }), events[i].mode == .since else { return false }
        events[i].allDay = false
        events[i].date = Schedule.wholeMinute(date)
        events[i].updatedAt = now
        return true
    }

    /// One-off countdowns that have ended. Reusable ones are left out: they are meant to stay.
    public func finishedIDs(now: Date, calendar: Calendar) -> Set<UUID> {
        Set(events.filter { !$0.reusable && Display.isFinished($0, now: now, calendar: calendar) }.map { $0.id })
    }

    /// Dashboard order: reusable countdowns first, then running countdowns (soonest first),
    /// then "time since" (most recent first), then ended countdowns (most recently ended first).
    public func dashboardOrder(now: Date, calendar: Calendar) -> [Event] {
        func group(_ e: Event) -> Int {
            if e.mode == .countdown && e.reusable { return 0 }
            if e.mode == .since { return 2 }
            return Display.isFinished(e, now: now, calendar: calendar) ? 3 : 1
        }
        func key(_ e: Event) -> Double {
            switch group(e) {
            case 0: return e.createdAt.timeIntervalSinceReferenceDate
            case 1: return e.date.timeIntervalSinceReferenceDate
            default: return -e.date.timeIntervalSinceReferenceDate
            }
        }
        return events.sorted { a, b in
            let ga = group(a), gb = group(b)
            if ga != gb { return ga < gb }
            let ka = key(a), kb = key(b)
            if ka != kb { return ka < kb }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// The countdown a new widget shows before anyone has picked one: the first on the dashboard
    /// of that kind.
    public func defaultEvent(mode: EventMode, now: Date, calendar: Calendar) -> Event? {
        dashboardOrder(now: now, calendar: calendar).first { $0.mode == mode }
    }

    /// Keeps a colour set for later. A set with the same colours is moved to the front, not doubled.
    public mutating func keep(theme: Theme) {
        savedThemes.removeAll { $0.sameColours(as: theme) }
        savedThemes.insert(theme, at: 0)
        if savedThemes.count > AppState.maxSavedThemes {
            savedThemes.removeLast(savedThemes.count - AppState.maxSavedThemes)
        }
    }

    public mutating func forget(theme: Theme) {
        savedThemes.removeAll { $0.sameColours(as: theme) }
    }
}
