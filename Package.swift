// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UniboardCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "UniboardCore", targets: ["UniboardCore"])],
    targets: [
        .target(name: "UniboardCore", path: "Shared", exclude: ["KeyboardPreviewImageExport.swift", "FontRuleFaceLoader.swift", "FontLibraryStorage.swift", "CustomFontStore.swift", "KeyboardSymbolPagesPager.swift", "KeyboardTouchFeedback.swift", "UnicodeFontSupport.swift", "KeyboardRepeatingDeleteControl.swift", "KeyboardTouchActionControl.swift", "KeyboardDocumentIdentity.swift", "KeyboardSelfSizingInputView.swift", "KeyboardVariantControl.swift", "KeyboardQueryControl.swift", "KeyboardInspectableInteraction.swift", "KeyboardHostInputTraits.swift", "KeyboardQueryInteraction.swift", "KeyboardQueryHoldControl.swift", "KeyboardPreviewCursorControl.swift", "PrivacyInfo.xcprivacy"], sources: ["FontLibraryContracts.swift", "CompanionAppRoute.swift", "UnicodeFontAssets.swift", "UnicodeCatalog.swift", "UnicodeSearchIndex.swift", "UnicodeSearchIndexStore.swift", "UnicodeEditionSettings.swift", "KeyboardKeySettings.swift", "EmojiCatalog.swift", "SymbolBoardStore.swift", "SymbolPageSettings.swift", "SymbolPageLayout.swift", "EditorReorder.swift", "FavoriteSync.swift", "KeyboardVariantPolicy.swift", "CharacterStore.swift", "KeyboardInteractionPolicy.swift", "KeyboardQueryHoldPolicy.swift", "KeyboardPreviewCursorPolicy.swift", "KeyboardTypingPolicy.swift", "KeyboardAlphabet.swift", "KeyboardTypingLayoutPolicy.swift", "KeyboardFooterLayoutPolicy.swift", "KeyboardEnglishInputPolicy.swift", "LocalPreferencePolicy.swift", "CatalogWorker.swift", "UCSUR.swift", "MainKeyboardArrangement.swift", "TOMLDocument.swift", "FontRules.swift", "SharedConfigurationLocation.swift", "FontRuleStore.swift", "FontRuleEditing.swift", "ImageColorSettings.swift", "AutoCapitalizationSetting.swift", "TextInspection.swift", "ConfigurationModel.swift", "ConfigurationCodec.swift", "ConfigurationDiff.swift", "FontPickerCatalog.swift", "StyleGrid.swift"], resources: [.process("Resources")]),
        .testTarget(name: "UniboardCoreTests", dependencies: ["UniboardCore"], path: "Tests")
    ]
)
