// The two widgets: "Time left" and "Time since". Each comes in a Lock Screen size (the block
// under the clock, and the single line above it) and two Home Screen sizes.

import SwiftUI
import WidgetKit
import CurtainCore

@main
struct CurtainWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
        SinceWidget()
    }
}

struct CountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CurtainEntry {
        .sample(.countdown)
    }

    func snapshot(for configuration: SelectCountdownIntent, in context: Context) async -> CurtainEntry {
        let first = WidgetData.entries(mode: .countdown, chosen: configuration.event?.id, now: Date()).entries.first
        // In the widget gallery, show an example rather than "No countdown".
        if let entry = first, !(context.isPreview && entry.display.state == .empty) { return entry }
        return .sample(.countdown)
    }

    func timeline(for configuration: SelectCountdownIntent, in context: Context) async -> Timeline<CurtainEntry> {
        WidgetData.timeline(mode: .countdown, chosen: configuration.event?.id, family: context.family)
    }
}

struct SinceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CurtainEntry {
        .sample(.since)
    }

    func snapshot(for configuration: SelectSinceIntent, in context: Context) async -> CurtainEntry {
        let first = WidgetData.entries(mode: .since, chosen: configuration.event?.id, now: Date()).entries.first
        if let entry = first, !(context.isPreview && entry.display.state == .empty) { return entry }
        return .sample(.since)
    }

    func timeline(for configuration: SelectSinceIntent, in context: Context) async -> Timeline<CurtainEntry> {
        WidgetData.timeline(mode: .since, chosen: configuration.event?.id, family: context.family)
    }
}

struct CountdownWidget: Widget {
    static let kind = "CurtainCountdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: CountdownWidget.kind, intent: SelectCountdownIntent.self,
                               provider: CountdownProvider()) { entry in
            CurtainWidgetView(entry: entry)
        }
        .configurationDisplayName("Time left")
        .description("A countdown, with a block for every hour left.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium])
        // Keep the countdown's colours where iOS would otherwise strip them (StandBy).
        .containerBackgroundRemovable(false)
    }
}

struct SinceWidget: Widget {
    static let kind = "CurtainSince"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SinceWidget.kind, intent: SelectSinceIntent.self,
                               provider: SinceProvider()) { entry in
            CurtainWidgetView(entry: entry)
        }
        .configurationDisplayName("Time since")
        .description("How long it has been, with a block for every hour gone by.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium])
        .containerBackgroundRemovable(false)
    }
}

struct CurtainWidgetView: View {
    let entry: CurtainEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .widgetURL(link)
            .containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium:
                    entry.theme.fill
                default:
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            InlineFace(display: entry.display, live: entry.live)
        case .accessoryRectangular:
            LockRectFace(display: entry.display, live: entry.live)
        case .systemMedium:
            HomeFace(display: entry.display, theme: entry.theme, caption: entry.caption, wide: true,
                     live: entry.live, fullColour: renderingMode == .fullColor)
        default:
            HomeFace(display: entry.display, theme: entry.theme, caption: nil, wide: false,
                     live: entry.live, fullColour: renderingMode == .fullColor)
        }
    }

    /// Tapping a widget opens its countdown in the app.
    private var link: URL? {
        guard let id = entry.eventID else { return URL(string: "curtain://open") }
        return URL(string: "curtain://event/\(id.uuidString)")
    }
}
