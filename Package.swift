// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SrizonVoice",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SrizonVoice", targets: ["SrizonVoice"])
    ],
    targets: [
        .executableTarget(
            name: "SrizonVoice",
            path: "Sources/SrizonVoice"
        )
    ]
)
