// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TesseraCore"),
        .executableTarget(name: "Tessera", dependencies: ["TesseraCore"]),
        .executableTarget(name: "TesseraChecks", dependencies: ["TesseraCore"]),
    ]
)
