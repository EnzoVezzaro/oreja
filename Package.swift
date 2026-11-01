// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Oreja",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Oreja", targets: ["OrejaApp"]),
        .executable(name: "oreja-probe", targets: ["OrejaAudioProbe"]),
        .library(name: "OrejaCore", targets: ["OrejaCore"]),
        .library(name: "OrejaAudio", targets: ["OrejaAudio"]),
        .library(name: "OrejaMedia", targets: ["OrejaMedia"]),
    ],
    targets: [
        .target(
            name: "OrejaCore",
            path: "packages/OrejaCore/Sources/OrejaCore"
        ),
        .target(
            name: "OrejaAudio",
            dependencies: ["OrejaCore"],
            path: "packages/OrejaAudio/Sources/OrejaAudio",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "OrejaMedia",
            dependencies: ["OrejaCore"],
            path: "packages/OrejaMedia/Sources/OrejaMedia",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "OrejaApp",
            dependencies: ["OrejaCore", "OrejaAudio", "OrejaMedia"],
            path: "apps/macos",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "OrejaAudioProbe",
            dependencies: ["OrejaCore", "OrejaAudio"],
            path: "tools/AudioProbe"
        ),
        .executableTarget(
            name: "OrejaTestRunner",
            dependencies: ["OrejaCore", "OrejaAudio", "OrejaMedia"],
            path: "Tests/OrejaTestRunner"
        ),
        .executableTarget(
            name: "OrejaIntegrationHarness",
            dependencies: ["OrejaCore", "OrejaAudio", "OrejaMedia"],
            path: "tools/IntegrationHarness"
        ),
    ],
    swiftLanguageModes: [.v6]
)
