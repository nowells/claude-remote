// swift-tools-version: 5.9
// ─────────────────────────────────────────────────────────────────────────────
// Swift Package for testing the shared ApprovalRequest model.
// Only the Shared target is included here — the Mac and iOS app targets require
// AppKit / UIKit and are built via the Xcode project (project.yml + xcodegen).
// ─────────────────────────────────────────────────────────────────────────────
import PackageDescription

let package = Package(
    name: "ClaudeRemote",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),
        .testTarget(
            name: "SharedTests",
            dependencies: ["Shared"],
            path: "Tests/SharedTests"
        ),
    ]
)
