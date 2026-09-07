// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vBoard",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "vBoard", targets: ["vBoard"])
    ],
    targets: [
        .executableTarget(
            name: "vBoard",
            path: "Sources/vBoard"
        )
    ]
)
