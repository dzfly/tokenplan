// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TalTokenPlan",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "TalTokenPlan",
            path: "Sources/TalTokenPlan",
            resources: [.copy("../../Resources/Info.plist")]
        ),
        .executableTarget(
            name: "CookieReaderHelper",
            path: "Sources/CookieReaderHelper",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
