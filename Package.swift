// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShuoXie",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "ShuoXie",
            path: "Sources/ShuoXie",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "ShuoXieTests",
            dependencies: ["ShuoXie"],
            path: "Tests/ShuoXieTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
