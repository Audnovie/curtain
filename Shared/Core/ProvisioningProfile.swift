// Reading the app groups out of a provisioning profile.
//
// A profile is the file a signing tool puts inside an app to say what the app may do. Tools that
// re-sign apps sometimes give the shared folder (the "app group") a new name; the profile always
// lists the names this copy was really signed for.

import Foundation

public enum ProvisioningProfile {
    /// The app groups listed in a profile. A profile is a signed envelope around a plain
    /// property list, so this finds the list inside it and reads that.
    public static func appGroups(in data: Data) -> [String] {
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
}
