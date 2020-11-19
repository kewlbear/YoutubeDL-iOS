// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "YoutubeDL-iOS",
    products: [
        .library(
            name: "YoutubeDL",
            targets: ["YoutubeDL"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kewlbear/FFmpeg-iOS.git", from: "0.0.1"),
                 .package(url: "https://github.com/kewlbear/PythonKit.git", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "YoutubeDL",
            dependencies: ["PythonKit", "FFmpeg-iOS"]),
        .testTarget(
            name: "YoutubeDLTests",
            dependencies: ["YoutubeDL"]),
    ]
)
