// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HearMe",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "HearMe",
            path: "Sources/HearMe",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "HearMeTests",
            dependencies: ["HearMe"],
            path: "Tests/HearMeTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
