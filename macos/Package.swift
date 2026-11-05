// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Konverter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Konverter", path: "Sources/Konverter")
    ]
)
