// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cellar",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "cellar",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "cellarTests",
            dependencies: ["cellar"]
        ),
    ]
)
