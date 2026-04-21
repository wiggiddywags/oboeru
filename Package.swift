// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Oboeru",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/weichsel/ZipFoundation.git",
            from: "0.9.19"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Oboeru",
            dependencies: [
                .product(name: "ZipFoundation", package: "ZipFoundation"),
            ],
            path: "Sources/Oboeru"
        ),
    ]
)
