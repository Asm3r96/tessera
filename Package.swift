// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.4.0"),
    ],
    targets: [
        .target(name: "TesseraCore"),
        .executableTarget(name: "Tessera", dependencies: ["TesseraCore", "KeyboardShortcuts"]),
        .executableTarget(name: "TesseraChecks", dependencies: ["TesseraCore"]),
    ]
)
