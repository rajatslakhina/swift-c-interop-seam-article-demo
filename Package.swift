// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InteropSeam",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InteropSeam", targets: ["InteropSeam"])
    ],
    targets: [
        .target(name: "InteropSeam"),
        .testTarget(name: "InteropSeamTests", dependencies: ["InteropSeam"])
    ]
)
