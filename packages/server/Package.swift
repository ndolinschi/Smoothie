// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmoothieServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SmoothieServer", targets: ["SmoothieServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.13.0")
    ],
    targets: [
        .executableTarget(
            name: "SmoothieServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            path: "Sources/SmoothieServer"
        )
    ]
)
