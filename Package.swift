// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Tessera", path: "Sources/Tessera")]
)
