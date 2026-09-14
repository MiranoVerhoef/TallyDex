// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ScanLabCore", platforms: [.macOS(.v14)], products: [.library(name: "ScanLabCore", targets: ["ScanLabCore"])], targets: [.target(name: "ScanLabCore", path: "Sources/Core"), .testTarget(name: "ScanLabCoreTests", dependencies: ["ScanLabCore"], path: "Tests")])
