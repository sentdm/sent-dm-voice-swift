// swift-tools-version: 5.9
import PackageDescription

// SentVoiceCore has no provider dependency and builds and tests on any Mac (`swift build --target
// SentVoiceCore`, `swift test`). SentVoice is the iOS client over the provider's SDK, a binary for iOS only,
// so it builds for the simulator or a device with xcodebuild, never with `swift build` on a Mac.
let package = Package(
    name: "SentVoice",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SentVoice", targets: ["SentVoice"]),
        .library(name: "SentVoiceCore", targets: ["SentVoiceCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sinch/sinch-ios-sdk-spm.git", exact: "5.47.17"),
    ],
    targets: [
        .target(name: "SentVoiceCore"),
        .target(
            name: "SentVoice",
            dependencies: [
                "SentVoiceCore",
                // iOS only: the binary has no macOS slice, so `swift test` on a Mac builds this target empty
                // (its sources are under `#if os(iOS)`) and xcodebuild builds the real thing for the simulator.
                .product(name: "SinchRTC", package: "sinch-ios-sdk-spm", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "SentVoiceCoreTests", dependencies: ["SentVoiceCore"]),
    ]
)
