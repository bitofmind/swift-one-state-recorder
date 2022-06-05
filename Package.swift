// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "swift-one-state-recorder",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(name: "OneStateRecorder", targets: ["OneStateRecorder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/bitofmind/swift-one-state", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "OneStateRecorder",
            dependencies: [
                .product(name: "OneState", package: "swift-one-state"),
            ]
        ),
    ]
)
