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
    targets: [
        .target(
            name: "CWin32"
        ),
        .target(
            name: "SwinitWin32",
            dependencies: [
                "CWin32",
                "SwinitCommon",
            ]
        ),

        .target(name: "CWayland"),
        .target(
            name: "SwinitWayland",
            dependencies: [
                "CWayland",
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
        
        .executableTarget(
            name: "SwinitExample",
            dependencies: ["Swinit"]
        ),
        .testTarget(
            name: "swinitTests",
            dependencies: ["Swinit"]
        ),
    ]
)
