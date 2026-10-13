// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FellowMac",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "AidenCore", targets: ["AidenCore"]),
    .executable(name: "FellowMac", targets: ["FellowMac"]),
  ],
  targets: [
    .target(name: "AidenCore"),
    .executableTarget(name: "FellowMac", dependencies: ["AidenCore"]),
    .testTarget(name: "AidenCoreTests", dependencies: ["AidenCore"]),
    .testTarget(name: "FellowMacTests", dependencies: ["FellowMac", "AidenCore"]),
  ]
)
