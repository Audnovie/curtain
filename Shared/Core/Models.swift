// What the app saves: countdowns, their colours, and a few settings.
// Everything here is plain Foundation so it can be tested with `swift test` on a Mac.

import Foundation

/// A countdown runs down to a date. A "time since" counts up from one.
public enum EventMode: String, Codable, CaseIterable, Sendable {
    case countdown
    case since
}

/// An sRGB colour, each part from 0 to 1. Saved as "#RRGGBB".
public struct RGB: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = RGB.clamp(r)
        self.g = RGB.clamp(g)
        self.b = RGB.clamp(b)
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }), let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255.0,
                  g: Double((v >> 8) & 0xFF) / 255.0,
                  b: Double(v & 0xFF) / 255.0)
    }

    /// For colours written in the code, where a typo should fail loudly in the tests.
    public init(_ hex: String) {
        self = RGB(hex: hex) ?? RGB(r: 1, g: 0, b: 1)
    }

    public var hex: String {
        func part(_ x: Double) -> String {
            let v = Int((RGB.clamp(x) * 255.0).rounded())
            let s = String(v, radix: 16, uppercase: true)
            return s.count == 1 ? "0" + s : s
        }
        return "#" + part(r) + part(g) + part(b)
    }

    public static let white = RGB(r: 1, g: 1, b: 1)
    public static let black = RGB(r: 0, g: 0, b: 0)

    static func clamp(_ x: Double) -> Double {
        if x.isNaN { return 0 }
        return min(1, max(0, x))
    }
}

extension RGB: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = RGB(hex: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a colour: \(s)")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

/// The colours of one card or Home Screen widget.
public struct Theme: Equatable, Hashable, Sendable {
    public var name: String
    public var background: RGB
    /// The second colour of a top-to-bottom blend. Nil for a flat colour.
    public var background2: RGB?
    /// Text.
    public var foreground: RGB
    /// The blocks of the bar.
    public var accent: RGB

    public init(name: String, background: RGB, background2: RGB? = nil, foreground: RGB, accent: RGB) {
        self.name = name
        self.background = background
        self.background2 = background2
        self.foreground = foreground
        self.accent = accent
    }
}

extension Theme: Codable {
    enum CodingKeys: String, CodingKey { case name, background, background2, foreground, accent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Theme.ember
        name = (try? c.decode(String.self, forKey: .name)) ?? "Custom"
        background = (try? c.decode(RGB.self, forKey: .background)) ?? fallback.background
        background2 = try? c.decode(RGB.self, forKey: .background2)
        foreground = (try? c.decode(RGB.self, forKey: .foreground)) ?? Contrast.text(on: background)
        accent = (try? c.decode(RGB.self, forKey: .accent)) ?? foreground
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(background, forKey: .background)
        try c.encodeIfPresent(background2, forKey: .background2)
        try c.encode(foreground, forKey: .foreground)
        try c.encode(accent, forKey: .accent)
    }
}

extension Theme {
    public static let ember = Theme(name: "Ember", background: RGB("#D42B3A"), background2: RGB("#A81E2B"),
                                    foreground: .white, accent: RGB("#FFD9D2"))
    public static let midnight = Theme(name: "Midnight", background: RGB("#1F2A44"), background2: RGB("#141B2D"),
                                       foreground: .white, accent: RGB("#7FB3FF"))
    public static let ocean = Theme(name: "Ocean", background: RGB("#0B5FA5"), background2: RGB("#0A3D7A"),
                                    foreground: .white, accent: RGB("#9AD7FF"))
    public static let lagoon = Theme(name: "Lagoon", background: RGB("#0C7170"), background2: RGB("#0A5A5F"),
                                     foreground: .white, accent: RGB("#A7F0E4"))
    public static let forest = Theme(name: "Forest", background: RGB("#1F6F43"), background2: RGB("#154D30"),
                                     foreground: .white, accent: RGB("#BFE8A9"))
    public static let sunset = Theme(name: "Sunset", background: RGB("#C2410C"), background2: RGB("#9A2F0A"),
                                     foreground: .white, accent: RGB("#FFD9A8"))
    public static let grape = Theme(name: "Grape", background: RGB("#6D28D9"), background2: RGB("#4C1D95"),
                                    foreground: .white, accent: RGB("#D9C7FF"))
    public static let rose = Theme(name: "Rose", background: RGB("#BE185D"), background2: RGB("#9D174D"),
                                   foreground: .white, accent: RGB("#FFD1E3"))
    public static let slate = Theme(name: "Slate", background: RGB("#334155"), background2: RGB("#1E293B"),
                                    foreground: .white, accent: RGB("#CBD5E1"))
    public static let paper = Theme(name: "Paper", background: RGB("#F5F1E8"), background2: RGB("#E9E2D3"),
                                    foreground: RGB("#1F2328"), accent: RGB("#B4432F"))

    public static let presets: [Theme] = [ember, midnight, ocean, lagoon, forest, sunset, grape, rose, slate, paper]

    /// True when the two would look the same on a card (the name doesn't count).
    public func sameColours(as other: Theme) -> Bool {
        background == other.background && background2 == other.background2
            && foreground == other.foreground && accent == other.accent
    }
}

/// One countdown or one "time since".
public struct Event: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var mode: EventMode
    /// Countdown: when it ends. Time since: when it began. Always a whole minute.
    public var date: Date
    /// Counts whole days and ignores the time of day.
    public var allDay: Bool
    /// A reusable countdown stays on the dashboard after it ends, ready to be set again.
    public var reusable: Bool
    /// The times it is usually set to, as minutes after midnight (17:00 is 1020). Sorted, no repeats.
    public var usualTimes: [Int]
    public var theme: Theme
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, mode: EventMode, date: Date, allDay: Bool = false,
                reusable: Bool = false, usualTimes: [Int] = [], theme: Theme = .ember,
                createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.mode = mode
        self.date = date
        self.allDay = allDay
        self.reusable = reusable
        self.usualTimes = usualTimes
        self.theme = theme
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public static let maxNameLength = 40
    public static let maxUsualTimes = 8

    /// Tidies what came from the editor or from a saved file: a trimmed name, a whole-minute date,
    /// usual times in order. `calendar` decides where a day begins for all-day events.
    public func normalized(calendar: Calendar) -> Event {
        var e = self
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        e.name = String(trimmed.prefix(Event.maxNameLength))
        if e.name.isEmpty { e.name = mode == .countdown ? "Countdown" : "Time since" }
        e.date = allDay ? calendar.startOfDay(for: date) : Schedule.wholeMinute(date)
        if mode == .since || allDay {
            e.reusable = false
            e.usualTimes = []
        }
        e.usualTimes = Schedule.tidy(usualTimes: e.usualTimes)
        return e
    }
}

extension Event: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, mode, date, allDay, reusable, usualTimes, theme, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Countdown"
        mode = (try? c.decode(EventMode.self, forKey: .mode)) ?? .countdown
        date = try c.decode(Date.self, forKey: .date)
        allDay = (try? c.decode(Bool.self, forKey: .allDay)) ?? false
        reusable = (try? c.decode(Bool.self, forKey: .reusable)) ?? false
        usualTimes = Schedule.tidy(usualTimes: (try? c.decode([Int].self, forKey: .usualTimes)) ?? [])
        theme = (try? c.decode(Theme.self, forKey: .theme)) ?? .ember
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? date
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }
}

public struct Settings: Equatable, Sendable {
    /// Cards in the app count seconds. Widgets never do.
    public var showSeconds: Bool
    /// The colours a new countdown starts with.
    public var defaultTheme: Theme

    public init(showSeconds: Bool = false, defaultTheme: Theme = .ember) {
        self.showSeconds = showSeconds
        self.defaultTheme = defaultTheme
    }
}

extension Settings: Codable {
    enum CodingKeys: String, CodingKey { case showSeconds, defaultTheme }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showSeconds = (try? c.decode(Bool.self, forKey: .showSeconds)) ?? false
        defaultTheme = (try? c.decode(Theme.self, forKey: .defaultTheme)) ?? .ember
    }
}

/// Everything in the one saved file.
public struct AppState: Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var events: [Event]
    /// Colour sets the person made and kept (from a wallpaper or the colour picker).
    public var savedThemes: [Theme]
    public var settings: Settings

    public init(events: [Event] = [], savedThemes: [Theme] = [], settings: Settings = Settings()) {
        self.version = AppState.currentVersion
        self.events = events
        self.savedThemes = savedThemes
        self.settings = settings
    }

    public static let maxSavedThemes = 24

    public func event(id: UUID) -> Event? {
        events.first { $0.id == id }
    }
}

extension AppState: Codable {
    enum CodingKeys: String, CodingKey { case version, events, savedThemes, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        // One damaged countdown shouldn't take the rest with it.
        let wrapped = try c.decode([Lossy<Event>].self, forKey: .events)
        events = wrapped.compactMap { $0.value }
        savedThemes = (try? c.decode([Theme].self, forKey: .savedThemes)) ?? []
        settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
    }
}

/// Decodes to nil instead of failing, so one bad item in a list is skipped.
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
