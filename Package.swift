// swift-tools-version: 6.4.0
import PackageDescription

let package = Package(
    name: "ScreenScribe",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ScreenScribe",
            path: "ScreenScribe",
            exclude: [
                "Assets.xcassets",
                "Info.entitlements",
                "Info.plist",
                "Screen Capture.aif",
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
