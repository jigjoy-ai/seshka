// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Seshka",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Checks for, downloads and installs new versions.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Seshka",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Seshka"
        )
    ]
)
