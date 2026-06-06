// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Swinit",
    products: [
        .library(
            name: "Swinit",
            targets: ["Swinit"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ongsalt/SwiftWayland", branch: "master")
    ],
    targets: [
        .target(
            name: "SwinitWin32",
            dependencies: [
                "SwinitCommon",
            ]
        ),

        .target(
            name: "SwinitWayland",
            dependencies: [
                .product(name: "SwiftWayland", package: "SwiftWayland"),
                "SwinitCommon",
            ]
        ),

        .target(
            name: "SwinitCommon"
        ),

        .target(
            name: "Swinit",
            dependencies: [
                "SwinitCommon",
                .byName(name: "SwinitWin32", condition: .when(platforms: [.windows])),
                .byName(name: "SwinitWayland", condition: .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "swinitTests",
            dependencies: ["Swinit"]
        ),
    ]
)
