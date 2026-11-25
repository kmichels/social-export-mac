// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SocialExportCore",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "SocialExportCore", targets: ["SocialExportCore"]),
    ],
    targets: [
        .target(name: "SocialExportCore"),
        .testTarget(name: "SocialExportCoreTests", dependencies: ["SocialExportCore"]),
    ],
    swiftLanguageModes: [.v6]
)
