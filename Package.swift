// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "AIUsageBar", platforms: [.macOS(.v14)], products: [
    .executable(name: "AIUsageBar", targets: ["AIUsageBar"])
], targets: [
    .executableTarget(name: "AIUsageBar"),
    .testTarget(name: "AIUsageBarTests", dependencies: ["AIUsageBar"])
], swiftLanguageModes: [.v5])
