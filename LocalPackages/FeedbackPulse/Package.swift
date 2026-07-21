// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeedbackPulse",
    platforms: [
        // Vendored copy: platform floor raised from iOS 14 / macOS 11 to iOS 16 /
        // macOS 12. The upstream SDK declared iOS 14 but its FeedbackView uses the
        // iOS 15-only `.alert(_:isPresented:actions:message:)` without an
        // availability guard, so compiling at the original iOS 14 floor failed.
        // Lunifer targets iOS 26.2, so a higher floor costs nothing.
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "FeedbackPulse",
            targets: ["FeedbackPulse"]
        ),
    ],
    targets: [
        .target(
            name: "FeedbackPulse",
            dependencies: [],
            path: "Sources/FeedbackPulse"
        ),
    ]
)
