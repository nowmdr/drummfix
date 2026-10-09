// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DrummFix",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DrummFix", targets: ["DrummFix"]),
        .executable(name: "DrummFixGuard", targets: ["DrummFixGuard"]),
        .executable(name: "DrummFixProbe", targets: ["DrummFixProbe"]),
    ],
    targets: [
        .target(name: "DrummFixCore"),
        .executableTarget(name: "DrummFix", dependencies: ["DrummFixCore"]),
        .executableTarget(name: "DrummFixGuard", dependencies: ["DrummFixCore"]),
        .executableTarget(name: "DrummFixProbe", dependencies: ["DrummFixCore"]),
        .executableTarget(name: "DrummFixTests", dependencies: ["DrummFixCore"], path: "Tests/DrummFixCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
