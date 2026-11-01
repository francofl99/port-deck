// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PortDeck",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "PortDeck", path: "Sources/PortDeck")
    ],
    swiftLanguageModes: [.v5]
)
