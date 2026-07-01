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
    traits: [
        .trait(name: "WaylandCSD"),
        .default(enabledTraits: ["WaylandCSD"])
    ],
    dependencies: [
        .package(url: "https://github.com/ongsalt/SwiftWayland", branch: "master", traits: ["XDG", "WP"])
    ],
    targets: [
        .systemLibrary(
            name: "CCairo",
            pkgConfig: "cairo",
            providers: [.apt(["libcairo2-dev"]), .brew(["cairo"])],
        ),

        .systemLibrary(
            name: "CXkbCommon",
            pkgConfig: "xkbcommon",
            providers: [.apt(["libxkbcommon-dev"])],
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
                .product(name: "WaylandClient", package: "SwiftWayland"),
                "SwinitCore",
                .target(name: "CCairo", condition: .when(platforms: [.linux], traits: ["WaylandCSD"])),
            ],
        ),

        .target(
            name: "SwinitCore"
        ),

        .target(
            name: "Swinit",
            dependencies: [
                "SwinitCore",
                .byName(name: "SwinitWin32", condition: .when(platforms: [.windows])),
                .byName(name: "SwinitWayland", condition: .when(platforms: [.linux])),
                .product(name: "WaylandClient", package: "SwiftWayland",
                         condition: .when(platforms: [.linux])),
                .byName(name: "CXkbCommon", condition: .when(platforms: [.linux])),
            ],
        ),
        .testTarget(
            name: "swinitTests",
            dependencies: ["Swinit"]
        ),
    ]
)
