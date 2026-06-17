// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Examples",
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/ongsalt/SwiftWayland", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "Examples",
            dependencies: [
                .product(name: "Swinit", package: "swinit"),
                .product(name: "WaylandClient", package: "SwiftWayland", condition: .when(platforms: [.linux])),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
