// Where the saved file lives.
//
// The app and its widgets are separate programs. iOS lets them share one folder (an "app group")
// when both are signed for it. Signing tools sometimes rename that group, so this looks for the
// group this copy was really signed with before falling back to the app's own folder.

import Foundation
import CurtainCore

enum SharedContainer {
    /// The group named in project.yml.
    static let buildTimeGroup = "group.io.github.audnovie.curtain"

    struct Location {
        /// The saved file.
        let file: URL
        /// False when this is the program's own folder, which the other program can't see.
        let shared: Bool
        let group: String?

        var folder: URL { file.deletingLastPathComponent() }
        /// A note the widgets leave each time iOS asks them for something to show.
        var widgetNote: URL { folder.appendingPathComponent("widget-seen.json") }
    }

    static let location: Location = resolve()

    static func candidateGroups() -> [String] {
        var out = [buildTimeGroup]
        // AltStore and SideStore rename the group and list the new name under this key.
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            out += alt
        }
        out += groupsInProvisioningProfile()
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// The groups this copy was signed for, read from the profile inside its own bundle.
    static func groupsInProvisioningProfile() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return [] }
        return groups(inProfile: data)
    }

    /// A provisioning profile is a signed envelope around a plain property list.
    static func groups(inProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: [], in: start.lowerBound..<data.endIndex)
        else { return [] }
        let body = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let any = try? PropertyListSerialization.propertyList(from: body, options: [], format: nil),
              let plist = any as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }

    static func resolve() -> Location {
        let fm = FileManager.default
        for group in candidateGroups() {
            if let base = fm.containerURL(forSecurityApplicationGroupIdentifier: group) {
                let dir = base.appendingPathComponent("Library/Application Support/Curtain", isDirectory: true)
                return Location(file: dir.appendingPathComponent(StateFile.fileName), shared: true, group: group)
            }
        }
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Curtain", isDirectory: true)
        return Location(file: dir.appendingPathComponent(StateFile.fileName), shared: false, group: nil)
    }
}

/// What a widget wrote the last time iOS asked it for something to show. The app reads this to
/// tell whether the widgets can see its data at all.
struct WidgetNote: Codable, Equatable {
    var at: Date
    var kind: String
    var family: String
    /// How many countdowns the widget could read.
    var events: Int

    static func read(from location: SharedContainer.Location) -> WidgetNote? {
        guard let data = try? Data(contentsOf: location.widgetNote) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetNote.self, from: data)
    }

    func write(to location: SharedContainer.Location) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(self) else { return }
        try? FileManager.default.createDirectory(at: location.folder, withIntermediateDirectories: true)
        try? data.write(to: location.widgetNote, options: .atomic)
    }
}
