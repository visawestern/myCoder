// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "myCoder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "myCoder", targets: ["myCoder"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "myCoder",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "myCoder/Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "myCoderTests",
            dependencies: ["myCoder"],
            path: "myCoder/Tests"
        )
    ]
)
