// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SrizonVoice",
    platforms: [
        .macOS(.v12)
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
