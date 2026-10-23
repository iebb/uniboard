// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UniboardCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "UniboardCore", targets: ["UniboardCore"])],
    targets: [
        .target(name: "UniboardCore", path: "Shared", exclude: ["KeyboardSymbolPagesPager.swift", "KeyboardTouchFeedback.swift", "UnicodeFontSupport.swift", "KeyboardRepeatingDeleteControl.swift", "KeyboardTouchActionControl.swift", "KeyboardDocumentIdentity.swift", "KeyboardSelfSizingInputView.swift", "KeyboardVariantControl.swift", "KeyboardQueryControl.swift", "KeyboardInspectableInteraction.swift", "KeyboardHostInputTraits.swift", "KeyboardQueryInteraction.swift", "PrivacyInfo.xcprivacy"], sources: ["CompanionAppRoute.swift", "UnicodeFontAssets.swift", "UnicodeCatalog.swift", "UnicodeEditionSettings.swift", "KeyboardKeySettings.swift", "EmojiCatalog.swift", "SymbolBoardStore.swift", "SymbolPageSettings.swift", "SymbolPageLayout.swift", "FavoriteSync.swift", "KeyboardVariantPolicy.swift", "CharacterStore.swift", "KeyboardInteractionPolicy.swift", "KeyboardTypingPolicy.swift", "KeyboardAlphabet.swift", "KeyboardTypingLayoutPolicy.swift", "KeyboardFooterLayoutPolicy.swift", "KeyboardEnglishInputPolicy.swift", "LocalPreferencePolicy.swift", "CatalogWorker.swift", "UCSUR.swift", "MainKeyboardArrangement.swift"], resources: [.process("Resources")]),
        .testTarget(name: "UniboardCoreTests", dependencies: ["UniboardCore"], path: "Tests")
    ]
)
