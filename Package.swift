// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cellar",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-testing", from: "0.12.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.0"),
    ],
    targets: [
        .executableTarget(
            name: "cellar",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "cellarTests",
            dependencies: [
                "cellar",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
