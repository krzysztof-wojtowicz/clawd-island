// swift-tools-version: 6.0
// Package manifest: pure core logic, the notch app, the Claude Code bridge CLI, and core tests (ADR-0001).
// Run tests with scripts/test.sh: with Command Line Tools only, swift-testing needs extra search paths.
import PackageDescription

let package = Package(
    name: "ClawdIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClawdCore"),
        .executableTarget(name: "ClawdIsland", dependencies: ["ClawdCore"]),
        .executableTarget(name: "clawd-bridge"),
        .testTarget(name: "ClawdCoreTests", dependencies: ["ClawdCore"]),
    ]
)
