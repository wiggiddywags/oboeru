// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Oboeru",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Oboeru",
            path: "Sources/Oboeru"
        ),
    ]
)
