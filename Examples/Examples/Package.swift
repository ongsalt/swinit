// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Examples",
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Examples",
            dependencies: [
                .product(name: "Swinit", package: "swinit")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
