// swift-tools-version:5.9
// The app's logic on its own (time maths, what a widget shows, colours, the saved file), so its
// tests can run with `swift test` on a Mac. The iPhone app and widgets are built from project.yml
// (XcodeGen) and use the same sources.
import PackageDescription

let package = Package(
    name: "CurtainCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "CurtainCore", targets: ["CurtainCore"]),
    ],
    targets: [
        .target(name: "CurtainCore", path: "Shared/Core"),
        .testTarget(name: "CoreTests", dependencies: ["CurtainCore"], path: "Tests/CoreTests"),
    ],
    swiftLanguageVersions: [.v5]
)
