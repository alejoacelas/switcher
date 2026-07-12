// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switcher",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Switcher", targets: ["Switcher"])],
    targets: [
        .executableTarget(name: "Switcher"),
        .testTarget(name: "SwitcherTests", dependencies: ["Switcher"]),
    ],
    swiftLanguageModes: [.v5]
)
