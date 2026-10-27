// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectBoard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ProjectBoard", targets: ["ProjectBoard"])],
    targets: [
        .target(name: "BoardCore"),
        .executableTarget(name: "ProjectBoard", dependencies: ["BoardCore"]),
        .executableTarget(name: "BoardCoreChecks", dependencies: ["BoardCore"], path: "Tests/BoardCoreTests")
    ]
)
