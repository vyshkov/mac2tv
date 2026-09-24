// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MKVAirPlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MKVAirPlay",
            targets: ["MKVAirPlay"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MKVAirPlay",
            dependencies: [],
            path: "Sources/MKVAirPlay"
        )
    ]
)
