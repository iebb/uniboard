// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UniboardCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "UniboardCore", targets: ["UniboardCore"])],
    targets: [
        .target(name: "UniboardCore", path: "Shared", exclude: ["CharacterStore.swift", "UnicodeFontSupport.swift", "PrivacyInfo.xcprivacy"], sources: ["UnicodeCatalog.swift", "EmojiCatalog.swift"], resources: [.process("Resources")]),
        .testTarget(name: "UniboardCoreTests", dependencies: ["UniboardCore"], path: "Tests")
    ]
)
