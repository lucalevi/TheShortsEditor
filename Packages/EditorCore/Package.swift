// swift-tools-version: 6.2
import PackageDescription

// AVFoundation's types aren't Sendable, so rendering code (and its tests) runs on the main actor,
// and async calls stay on the caller's actor instead of hopping to a background executor.
let mainActorByDefault: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "EditorCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "RenderEngine", targets: ["RenderEngine"]),
    ],
    targets: [
        // Pure project model and edit operations. No AVFoundation, no UI.
        .target(name: "EditorCore"),
        // Builds playable/exportable AVFoundation objects from an EditorCore project.
        .target(name: "RenderEngine", dependencies: ["EditorCore"], swiftSettings: mainActorByDefault),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
        .testTarget(name: "RenderEngineTests", dependencies: ["RenderEngine"], swiftSettings: mainActorByDefault),
    ]
)
