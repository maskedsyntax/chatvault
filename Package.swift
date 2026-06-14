// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChatVault",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .executableTarget(
            name: "ChatVault",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ChatVaultTests",
            dependencies: ["ChatVault"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
