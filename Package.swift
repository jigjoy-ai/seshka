// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Seshka",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Seshka", path: "Sources/Seshka")
    ]
)
