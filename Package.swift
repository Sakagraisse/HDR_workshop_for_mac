
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "HDRUtility",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "HDRUtilityKit", targets: ["HDRUtilityKit"]),
        .executable(name: "HDRUtility", targets: ["HDRUtility"])
    ],
    targets: [
        .target(
            name: "HDRUtilityKit",
            path: "Sources/HDRUtility"
        ),
        .executableTarget(
            name: "HDRUtility",
            dependencies: ["HDRUtilityKit"],
            path: "Sources/HDRUtilityExecutable"
        ),
        .testTarget(
            name: "HDRUtilityTests",
            dependencies: ["HDRUtilityKit"],
            path: "Tests/HDRUtilityTests"
        )
    ]
)
