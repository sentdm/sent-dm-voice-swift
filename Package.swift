// swift-tools-version: 5.9
import PackageDescription

// SentVoiceCore has no provider dependency and builds and tests on any Mac. The iOS client over the
// provider's SDK is the SentVoice target, added once the core is in place.
let package = Package(
    name: "SentVoice",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SentVoiceCore", targets: ["SentVoiceCore"]),
    ],
    targets: [
        .target(name: "SentVoiceCore"),
        .testTarget(name: "SentVoiceCoreTests", dependencies: ["SentVoiceCore"]),
    ]
)
