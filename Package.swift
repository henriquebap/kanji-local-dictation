// swift-tools-version: 6.2
// Para abrir no Xcode. O build oficial é `make app` (swiftc direto, sem SwiftPM).
import PackageDescription

let package = Package(
    name: "Kanji",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Kanji"),
    ]
)
