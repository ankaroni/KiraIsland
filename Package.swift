// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KiraIsland",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "KiraIsland", targets: ["KiraIsland"])
    ],
    targets: [
        .executableTarget(
            name: "KiraIsland",
            path: "Sources/KiraIsland"
        )
    ]
)
