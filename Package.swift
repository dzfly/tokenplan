// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TalTokenPlan",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .executableTarget(
            name: "TalTokenPlan",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
