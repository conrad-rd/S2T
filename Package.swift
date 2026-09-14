// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "S2T",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "S2T", targets: ["S2TApp"])],
    dependencies: [.package(url: "https://github.com/joogps/Glur.git", revision: "ba4f05d3c9a608ec773b9305f2af6089390de68a")],
    targets: [
        .target(name: "S2TCore", resources: [.copy("Resources/ChromaPresets")]),
        .executableTarget(name: "S2TApp", dependencies: ["S2TCore", .product(name: "GlurBackdrop", package: "Glur")]),
        .testTarget(name: "S2TCoreTests", dependencies: ["S2TCore"])
    ],
    swiftLanguageModes: [.v5]
)
