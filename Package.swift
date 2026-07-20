// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmdTab",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CmdTab", targets: ["CmdTab"])],
    targets: [
        .executableTarget(name: "CmdTab"),
        .testTarget(name: "CmdTabTests", dependencies: ["CmdTab"]),
    ],
    swiftLanguageModes: [.v5]
)
