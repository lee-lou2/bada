// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mal2geul",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Mal2geul", path: "Sources/Mal2geul"),
    ]
)
