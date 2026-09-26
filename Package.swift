// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bada",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Bada", path: "Sources/Bada"),
    ]
)
