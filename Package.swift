// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptBoard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "promptboard", targets: ["PromptBoardCLI"]),
        .executable(name: "PromptBoardApp", targets: ["PromptBoardApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
    ],
    targets: [
        .target(name: "PromptBoardKit"),
        .executableTarget(name: "PromptBoardApp", dependencies: ["PromptBoardKit"]),
        .executableTarget(
            name: "PromptBoardCLI",
            dependencies: [
                "PromptBoardKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "PromptBoardKitTests", dependencies: ["PromptBoardKit"]),
    ]
)
