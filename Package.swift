// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UnifiedAudioControl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "UnifiedAudioControl", targets: ["UnifiedAudioControl"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DDCSupport",
            dependencies: [],
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .executableTarget(
            name: "UnifiedAudioControl",
            dependencies: ["DDCSupport"],
            path: "Sources/UnifiedAudioControl",
            resources: [],
            linkerSettings: [
                .unsafeFlags([
                    "-F/System/Library/PrivateFrameworks",
                    "-framework", "DisplayServices",
                    "-framework", "CoreDisplay",
                    "-framework", "IOKit",
                    "-framework", "CoreGraphics",
                    "-framework", "AppKit",
                    "-framework", "IOBluetooth"
                ])
            ]
        )
    ]
)
