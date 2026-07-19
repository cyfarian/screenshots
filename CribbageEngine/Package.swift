// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CribbageEngine",
    platforms: [
        .iOS(.v17), .macOS(.v14),
    ],
    products: [
        .library(name: "CribbageEngine", targets: ["CribbageEngine"]),
    ],
    targets: [
        .target(name: "CribbageEngine"),
        .testTarget(name: "CribbageEngineTests", dependencies: ["CribbageEngine"]),
    ]
)
