// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DroidMirror",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DroidMirror",
            targets: ["DroidMirror"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DroidMirror",
            path: "Sources/DroidMirror",
            exclude: [
                "Resources/Entitlements.plist",
                "Resources/Info.plist"
            ],
            resources: [
                .copy("Resources/bin"),
                .copy("Resources/licenses")
            ]
        ),
        .testTarget(
            name: "DroidMirrorTests",
            dependencies: ["DroidMirror"],
            path: "Tests/DroidMirrorTests"
        )
    ]
)
