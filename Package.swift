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
        .systemLibrary(
            name: "CCairo",
            pkgConfig: "cairo",
            providers: [.apt(["libcairo2-dev"]), .brew(["cairo"])]
        ),

        .target(
            name: "SwinitWin32",
            dependencies: [
                "SwinitCore",
            ]
        ),

        .target(
            name: "SwinitWayland",
            dependencies: [
                .product(name: "SwiftWayland", package: "SwiftWayland"),
                "SwinitCore",
                .target(name: "CCairo", condition: .when(platforms: [.linux])),
            ]
        ),

        .target(
            name: "SwinitCore"
        ),

        .target(
            name: "Swinit",
            dependencies: [
                "SwinitCore",
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
