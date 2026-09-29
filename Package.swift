// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "S2T",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "S2T", targets: ["S2TApp"]), .executable(name: "S2TBench", targets: ["S2TBenchApp"])],
    dependencies: [.package(url: "https://github.com/joogps/Glur.git", revision: "ba4f05d3c9a608ec773b9305f2af6089390de68a")],
    targets: [
        .target(name: "S2TCore", resources: [.copy("Resources/ChromaPresets"), .copy("Resources/OpenRouterReasoning.json")]),
        .target(name: "S2TBenchCore", dependencies: ["S2TCore"]),
        .executableTarget(name: "S2TApp", dependencies: ["S2TCore", "S2TBenchCore", .product(name: "GlurBackdrop", package: "Glur")]),
        .executableTarget(name: "S2TBenchApp", dependencies: ["S2TCore", "S2TBenchCore"]),
        .testTarget(name: "S2TCoreTests", dependencies: ["S2TCore"]),
        .testTarget(name: "S2TBenchTests", dependencies: ["S2TBenchCore"])
    ],
    swiftLanguageModes: [.v5]
)
