// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Oboeru",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/open-spaced-repetition/swift-fsrs.git",
            from: "5.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Oboeru",
            dependencies: [
                .product(name: "FSRS", package: "swift-fsrs"),
            ],
            path: "Sources/Oboeru",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
