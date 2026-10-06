// swift-tools-version: 5.9
import PackageDescription

// CodexBridger has no external dependencies on purpose: it must build and run
// offline, and everything it needs (JSON, file IO, SwiftUI) ships with the OS.
//
// The SwiftUI layer is a separate library so component behaviour and layout can be
// tested headlessly, without launching the app or driving the UI.
let package = Package(
    name: "CodexBridger",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexBridger", targets: ["CodexBridger"]),
        .library(name: "CodexBridgerCore", targets: ["CodexBridgerCore"]),
        .library(name: "CodexBridgerUI", targets: ["CodexBridgerUI"])
    ],
    targets: [
        .target(
            name: "CodexBridgerCore",
            path: "Sources/CodexBridgerCore"
        ),
        .target(
            name: "CodexBridgerUI",
            dependencies: ["CodexBridgerCore"],
            path: "Sources/CodexBridgerUI"
        ),
        .executableTarget(
            name: "CodexBridger",
            dependencies: ["CodexBridgerCore", "CodexBridgerUI"],
            path: "Sources/CodexBridger"
        ),
        .testTarget(
            name: "CodexBridgerCoreTests",
            dependencies: ["CodexBridgerCore"],
            path: "Tests/CodexBridgerCoreTests"
        ),
        .testTarget(
            name: "CodexBridgerUITests",
            dependencies: ["CodexBridgerUI", "CodexBridgerCore"],
            path: "Tests/CodexBridgerUITests"
        )
    ]
)
