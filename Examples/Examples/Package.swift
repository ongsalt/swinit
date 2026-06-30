// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Examples",
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/ongsalt/SwiftWayland", branch: "master", traits: ["XDG", "WP"]),
    ],
    targets: [
        .systemLibrary(
            name: "CairoLib",
            pkgConfig: "cairo",
            providers: [.apt(["libcairo2-dev"]), .brew(["cairo"])]
        ),
        .executableTarget(
            name: "Examples",
            dependencies: [
                .product(name: "Swinit", package: "swinit"),
                .product(name: "WaylandClient", package: "SwiftWayland", condition: .when(platforms: [.linux])),
            ]
        ),
        .executableTarget(
            name: "CrashGnome",
            dependencies: [
                .product(name: "WaylandClient", package: "SwiftWayland"),
            ],
            exclude: ["crash_gnome.c"]
        ),
        .executableTarget(
            name: "CrashGnomeUI",
            dependencies: [
                .product(name: "Swinit", package: "swinit"),
                .product(name: "WaylandClient", package: "SwiftWayland"),
                "CairoLib",
            ],
            path: "Sources/CrashGnomeUI"
        ),
    ],
    swiftLanguageModes: [.v6]
)
