// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptBoard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PromptBoardKit"),
        .executableTarget(name: "PromptBoard", dependencies: ["PromptBoardKit"]),
        .testTarget(name: "PromptBoardKitTests", dependencies: ["PromptBoardKit"]),
    ]
)
