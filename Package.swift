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
        .package(url: "https://github.com/kewlbear/FFmpeg-iOS.git", .branch("main")),
                 .package(url: "https://github.com/kewlbear/PythonKit.git", .branch("master")),
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
