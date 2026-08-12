// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Branch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Branch", targets: ["Branch"])
    ],
    targets: [
        .executableTarget(name: "Branch"),
        .testTarget(name: "BranchTests", dependencies: ["Branch"])
    ]
)
