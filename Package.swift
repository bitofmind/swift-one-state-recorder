// swift-tools-version:5.6

import PackageDescription

#if swift(>=5.7)
let swiftSettings: [SwiftSetting] = []//[SwiftSetting.unsafeFlags(["-Xfrontend", "-warn-concurrency"])]
#else
let swiftSettings: [SwiftSetting] = []
#endif

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
        .package(url: "https://github.com/bitofmind/swift-one-state", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "OneStateRecorder",
            dependencies: [
                .product(name: "OneState", package: "swift-one-state"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
