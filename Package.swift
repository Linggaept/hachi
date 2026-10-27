// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hachi",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "TodoParser",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Hachi",
            dependencies: ["TodoParser"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "TodoParserTests",
            dependencies: ["TodoParser"],
            // Tanpa Xcode, plugin macro @Test dari Command Line Tools harus ditunjuk manual.
            swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]
        ),
        .testTarget(
            name: "HachiTests",
            dependencies: ["Hachi"],
            swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]
        ),
    ]
)
