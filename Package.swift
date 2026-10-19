// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UniboardCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "UniboardCore", targets: ["UniboardCore"])],
    targets: [
        .target(name: "UniboardCore", path: "Shared", exclude: ["KeyboardTouchFeedback.swift", "UnicodeFontSupport.swift", "KeyboardResizeHandleControl.swift", "KeyboardRepeatingDeleteControl.swift", "KeyboardTouchActionControl.swift", "KeyboardDocumentIdentity.swift", "KeyboardSelfSizingInputView.swift", "KeyboardVariantControl.swift", "KeyboardQueryControl.swift", "KeyboardInspectableInteraction.swift", "KeyboardHostInputTraits.swift", "KeyboardQueryInteraction.swift", "PrivacyInfo.xcprivacy"], sources: ["CompanionAppRoute.swift", "UnicodeCatalog.swift", "UnicodeEditionSettings.swift", "KeyboardKeySettings.swift", "EmojiCatalog.swift", "SymbolBoardStore.swift", "FavoriteSync.swift", "KeyboardVariantPolicy.swift", "CharacterStore.swift", "KeyboardInteractionPolicy.swift", "KeyboardResizeStepPolicy.swift", "KeyboardTypingPolicy.swift", "KeyboardTypingLayoutPolicy.swift", "KeyboardFooterLayoutPolicy.swift", "KeyboardEnglishInputPolicy.swift", "LocalPreferencePolicy.swift", "CatalogWorker.swift"], resources: [.process("Resources")]),
        .testTarget(name: "UniboardCoreTests", dependencies: ["UniboardCore"], path: "Tests")
    ]
)
