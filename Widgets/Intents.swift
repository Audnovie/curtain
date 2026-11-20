// The "which countdown?" choice shown when a widget is edited (long-press the widget, Edit Widget).

import AppIntents
import WidgetKit
import CurtainCore

struct CountdownChoice: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Countdown"
    static var defaultQuery = CountdownChoiceQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CountdownChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CountdownChoice] {
        WidgetData.choices(mode: .countdown)
            .filter { identifiers.contains($0.id.uuidString) }
            .map { CountdownChoice(id: $0.id.uuidString, name: $0.name) }
    }

    func suggestedEntities() async throws -> [CountdownChoice] {
        WidgetData.choices(mode: .countdown).map { CountdownChoice(id: $0.id.uuidString, name: $0.name) }
    }

    func defaultResult() async -> CountdownChoice? {
        WidgetData.choices(mode: .countdown).first.map { CountdownChoice(id: $0.id.uuidString, name: $0.name) }
    }
}

struct SelectCountdownIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Countdown"
    static var description = IntentDescription("Choose which countdown this widget shows.")

    @Parameter(title: "Countdown")
    var event: CountdownChoice?
}

struct SinceChoice: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Time since"
    static var defaultQuery = SinceChoiceQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SinceChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SinceChoice] {
        WidgetData.choices(mode: .since)
            .filter { identifiers.contains($0.id.uuidString) }
            .map { SinceChoice(id: $0.id.uuidString, name: $0.name) }
    }

    func suggestedEntities() async throws -> [SinceChoice] {
        WidgetData.choices(mode: .since).map { SinceChoice(id: $0.id.uuidString, name: $0.name) }
    }

    func defaultResult() async -> SinceChoice? {
        WidgetData.choices(mode: .since).first.map { SinceChoice(id: $0.id.uuidString, name: $0.name) }
    }
}

struct SelectSinceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Time since"
    static var description = IntentDescription("Choose which \"time since\" this widget shows.")

    @Parameter(title: "Time since")
    var event: SinceChoice?
}
