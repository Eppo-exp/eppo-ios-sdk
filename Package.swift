// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EppoFlagging",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "EppoFlagging",
            targets: ["EppoFlagging"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/ddddxxx/Semver", from: "0.2.1"),
        .package(url: "https://github.com/AliSoftware/OHHTTPStubs", .upToNextMajor(from: "9.0.0"))

    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "EppoFlagging",
            dependencies: ["Semver"],
            path: "./Sources/eppo"
        ),
        .testTarget(
            name: "EppoFlaggingTests",
            dependencies: [
                "EppoFlagging",
                .product(name: "OHHTTPStubs", package: "OHHTTPStubs"),
                .product(name: "OHHTTPStubsSwift", package: "OHHTTPStubs")
            ],
            path: "./Tests/eppo",
            resources: [
                .copy("Resources")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
