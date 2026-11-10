#if os(macOS)
import Foundation
import XCTest

/// Source guard only; rendered shelf bounds and blur need Simulator verification.
final class KeyboardEnglishShelfSourceTests: XCTestCase {
    private func controllerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Keyboard/KeyboardViewController.swift"),
                          encoding: .utf8)
    }

    private func shelfSource() throws -> String {
        let text = try controllerSource()
        let start = try XCTUnwrap(text.range(of: "    private var englishShelf: some View {"))
        let end = try XCTUnwrap(text.range(of: "    private var conversionShelf: some View {",
                                          range: start.upperBound..<text.endIndex))
        return String(text[start.lowerBound..<end.lowerBound])
    }

    func testReleaseGateKeepsEnglishRuntimeAndGeometryColdWithoutChangingLiteralTraits() throws {
        let text = try controllerSource()
        XCTAssertTrue(text.contains("LanguageInputSettings.englishAssistanceAvailable && language.mode == .direct"))
        XCTAssertFalse(text.contains("language.preferences.englishSuggestions"))
        XCTAssertFalse(text.contains("language.preferences.englishAutocorrection"))
        XCTAssertTrue(text.contains("suggestionsEnabled: language.preferences.effectiveEnglishSuggestions"))
        XCTAssertTrue(text.contains("autocorrectionEnabled: language.preferences.effectiveEnglishAutocorrection"))
        XCTAssertTrue(text.contains("if let self, self.englishSurfaceAvailable, self.english.hasImmediateUndo {"))
        XCTAssertTrue(text.contains("&& (language.mode != .direct || LanguageInputSettings.englishAssistanceAvailable)"))
        XCTAssertTrue(text.contains("&& (language.preferences.effectiveEnglishSuggestions || language.preferences.effectiveEnglishAutocorrection)"),
                      "Saved deferred switches must not affect Direct Typing key sizing")
        let start = try XCTUnwrap(text.range(of: "    private var permitsEnglishAssistance: Bool {"))
        let end = try XCTUnwrap(text[start.upperBound...].firstIndex(of: "}"))
        XCTAssertFalse(text[start.lowerBound...end].contains("englishAssistanceAvailable"),
                       "The independent host/literal capitalization policy stays unchanged")
        XCTAssertTrue(text.contains("? insertOrdinaryEnglish(text) : insertHostText(text)"))

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let coordinator = try String(contentsOf: root.appendingPathComponent("Keyboard/KeyboardEnglishCorrectionCoordinator.swift"), encoding: .utf8)
        XCTAssertTrue(coordinator.contains("private lazy var provider: any EnglishSuggestionProviding = suppliedProvider ?? EnglishSuggestionProvider()"))
        XCTAssertFalse(coordinator.contains("self.init(provider: EnglishSuggestionProvider()"),
                       "Constructing/invalidation of the adapter must not instantiate UITextChecker")
    }

    func testReleaseHidesDeferredSettingsAndPickerOptionsWithoutFilteringSavedWords() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let languages = try String(contentsOf: root.appendingPathComponent("App/LanguagesView.swift"), encoding: .utf8)
        XCTAssertTrue(languages.contains("ForEach(LanguageInputSettings.visibleModeOrder,"))
        XCTAssertTrue(languages.contains("if LanguageInputSettings.englishAssistanceAvailable {\n                Section(\"English\")"))
        XCTAssertTrue(languages.contains("if mode == .direct && LanguageInputSettings.englishAssistanceAvailable {"))
        XCTAssertTrue(languages.contains("Mandarin is an optional download"))
        XCTAssertTrue(languages.contains("All five are downloaded together and checked before use."))
        XCTAssertTrue(languages.contains("Nothing downloads automatically."))
        XCTAssertFalse(languages.contains("Download Size · jichu + zi"))
        XCTAssertFalse(languages.contains("already bundled and verified locally"))
        let words = try String(contentsOf: root.appendingPathComponent("App/MyWordsView.swift"), encoding: .utf8)
        let pickerStart = try XCTUnwrap(words.range(of: "private struct WordsModePicker: View {"))
        let pickerEnd = try XCTUnwrap(words.range(of: "private struct WordsNewDictionary", range: pickerStart.upperBound..<words.endIndex))
        let picker = words[pickerStart.lowerBound..<pickerEnd.lowerBound]
        XCTAssertTrue(picker.contains("ForEach(LanguageInputSettings.visibleModeOrder,"))
        XCTAssertFalse(picker.contains("koreanPending"))
        let collectionsStart = try XCTUnwrap(words.range(of: "    private var collections:"))
        let collectionsEnd = try XCTUnwrap(words.range(of: "    var body:", range: collectionsStart.upperBound..<words.endIndex))
        XCTAssertFalse(words[collectionsStart.lowerBound..<collectionsEnd.lowerBound].contains("visibleModeOrder"),
                       "Existing deferred-language dictionaries remain accessible and are never deleted")
        let controller = try controllerSource()
        XCTAssertTrue(controller.contains("ids += language.enabledModes.filter"), "Keep hold-Space selection of enabled actual packs")
        XCTAssertTrue(controller.contains("if englishSurfaceAvailable && model.compositionShelfHeight == 0 {"))
        XCTAssertTrue(controller.contains(": \"Tap to insert a space. Hold for keyboard choices.\","))
    }

    func testEnglishScrollAndButtonsCannotAddEdgeBlurOrBorderedStyleHeight() throws {
        let shelf = try shelfSource()
        XCTAssertTrue(shelf.contains(".keyboardUnmaskedScrollEdges()\n        .frame(height: 44)"))
        XCTAssertTrue(shelf.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(shelf.contains(".accessibilityIdentifier(\"keyboard.english.shelf\")"))
        XCTAssertFalse(shelf.contains(".bordered"))
        XCTAssertEqual(shelf.components(separatedBy: ".frame(minWidth: 44, minHeight: 44, maxHeight: 44)").count - 1, 1,
                       "Undo keeps its existing complete 44-point surface; suggestions use the shared minimum-44 label")
        XCTAssertEqual(shelf.components(separatedBy: ".background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))").count - 1, 1,
                       "Only the unchanged Undo recovery control retains its previous surface")
        XCTAssertEqual(shelf.components(separatedBy: ".contentShape(Rectangle())").count - 1, 1)
        XCTAssertFalse(shelf.contains("minimumScaleFactor"))
        XCTAssertTrue(shelf.contains("Text(status).font(.footnote)"))
        XCTAssertFalse(shelf.contains("Text(status).font(.system(size:"))
        XCTAssertTrue(shelf.contains(".padding(.horizontal, 8)"))
        XCTAssertTrue(shelf.contains(".foregroundStyle(Self.englishStatusInk)"))
        XCTAssertFalse(shelf.contains("KeyboardLanguageInformativeInk.secondary"))
        XCTAssertFalse(shelf.contains("VStack"), "English content is one 44-point row, never a status row above choices")
        XCTAssertFalse(shelf.contains("compositionShelfHeight"))
        XCTAssertFalse(shelf.contains(".opacity("))
    }

    func testOnlyActionableEnglishCellsUseSharedNaturalWidthFlatCandidatePresentation() throws {
        let shelf = try shelfSource()
        let start = try XCTUnwrap(shelf.range(of: "                if model.englishCanReplace {"))
        let end = try XCTUnwrap(shelf.range(of: "                if suggestionsUnavailable", range: start.upperBound..<shelf.endIndex))
        let choices = shelf[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(choices.contains("HStack(spacing: 0)"))
        XCTAssertTrue(choices.contains("if index > 0 { KeyboardCandidateDivider() }"))
        XCTAssertTrue(choices.contains("Button { controller?.chooseEnglish(suggestion, revision: revision) } label: {\n                                KeyboardCandidateText(output: suggestion)\n                            }"))
        XCTAssertTrue(choices.contains(".buttonStyle(KeyboardCandidateButtonStyle())"))
        for forbidden in ["RoundedRectangle", ".background(", ".lineLimit(", "maxWidth:", "minimumScaleFactor"] {
            XCTAssertFalse(choices.contains(forbidden), "No extra cards, cell caps or truncation in actionable English cells")
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let shared = try String(contentsOf: root.appendingPathComponent("Keyboard/KeyboardConversionViews.swift"), encoding: .utf8)
        let labelStart = try XCTUnwrap(shared.range(of: "struct KeyboardCandidateText: View {"))
        let labelEnd = try XCTUnwrap(shared.range(of: "private struct ConversionDisplaySnapshot", range: labelStart.upperBound..<shared.endIndex))
        let label = shared[labelStart.lowerBound..<labelEnd.lowerBound]
        XCTAssertTrue(label.contains("@ScaledMetric(relativeTo: .title3) private var outputSize = 20.0"))
        XCTAssertTrue(label.contains("var pending = false"), "English does not invent a conversion pending default")
        XCTAssertTrue(label.contains("Text(verbatim: output)"))
        XCTAssertTrue(label.contains(".fixedSize(horizontal: !expanded, vertical: expanded)"))
        XCTAssertTrue(label.contains(".padding(.horizontal, 12)"))
        XCTAssertTrue(label.contains("minHeight: 44, maxHeight: expanded ? nil : 44"))
    }

    func testEnglishStatusHasDedicatedSolidInkAndKeepsAllowedDynamicTypeRange() throws {
        let text = try controllerSource()
        let start = try XCTUnwrap(text.range(of: "    private static let englishStatusInk ="))
        let end = try XCTUnwrap(text.range(of: "\n    var body:", range: start.upperBound..<text.endIndex))
        let ink = text[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(ink.contains("traits.userInterfaceStyle == .dark"))
        XCTAssertTrue(ink.contains("UIColor(red: 177.0 / 255, green: 177.0 / 255, blue: 186.0 / 255, alpha: 1)"))
        XCTAssertTrue(ink.contains("UIColor(red: 84.0 / 255, green: 84.0 / 255, blue: 93.0 / 255, alpha: 1)"))
        XCTAssertFalse(ink.contains(".opacity("))
        XCTAssertTrue(text.contains(".dynamicTypeSize(.xSmall ... .xxxLarge)"))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let conversion = try String(contentsOf: root.appendingPathComponent("Keyboard/KeyboardConversionViews.swift"),
                                    encoding: .utf8)
        XCTAssertTrue(conversion.contains("UIColor(red: 98.0 / 255, green: 98.0 / 255, blue: 107.0 / 255, alpha: 1)"),
                      "Generic app/recovery informative ink stays #62626B; candidate captions have a separate tray token")
        XCTAssertFalse(conversion.contains("englishStatusInk"))
    }

    func testEnglishFullBandRemovesTopShelfAndContentPaddingOnlyWhileVisible() throws {
        let text = try controllerSource()
        let start = try XCTUnwrap(text.range(of: "    private var showsCompositionShelf: Bool {"))
        let end = try XCTUnwrap(text.range(of: "        .accessibilityElement(children: .contain)",
                                          range: start.upperBound..<text.endIndex))
        let layout = text[start.lowerBound..<end.lowerBound]
        for guardrail in [
            "!model.showsUnicode && !model.expandedConversion && !model.finishingConversion",
            "&& !isConversionLoading && !needsConversionRecovery && model.compositionShelfHeight > 0",
            "private var showsEnglishShelf: Bool { showsCompositionShelf && language.mode == .direct }",
            "private var typingTopInset: CGFloat { showsEnglishShelf ? 0 : 4 }",
            "private var typingContentTopGap: CGFloat { showsEnglishShelf ? 0 : contentGap }",
            "if showsCompositionShelf {\n                    if showsEnglishShelf { englishShelf }\n                    else {\n                        conversionShelf\n                        Color.clear.frame(height: 4).accessibilityHidden(true)",
            "Color.clear.frame(height: typingContentTopGap).accessibilityHidden(true)",
            ".padding(.top, typingTopInset)",
            "Color.clear.frame(height: contentGap).accessibilityHidden(true)\n                controls",
            "textPreviewRow.frame(height: headerHeight)",
            "toolbar.frame(height: headerHeight)",
            ".padding(.bottom, 6)"
        ] {
            XCTAssertTrue(layout.contains(guardrail), "Full English band = 0 + 44 + 0 + 0: \(guardrail)")
        }
        XCTAssertTrue(text.contains("prefersCompactShelf: prefersCompactShelf, englishSingleRow: language.mode == .direct)"),
                      "Root height and merge fit must remove the same 12 points, not donate them to keys")
    }

    func testEnglishShelfHidesUnavailableChoicesButKeepsIndependentRevisionValidatedUndo() throws {
        let shelf = try shelfSource()
        for guardrail in [
            "let revision = model.englishRevision",
            "controller?.undoEnglish(revision: revision)",
            "controller?.chooseEnglish(suggestion, revision: revision)",
            ".disabled(!model.englishCanReplace)",
            "Restores your spelling and removes the triggering delimiter.",
            "let suggestionsUnavailable = !model.englishSuggestions.isEmpty && !model.englishCanReplace",
            "let status = suggestionsUnavailable ? \"Suggestions unavailable here.\" : model.englishStatus",
            "if suggestionsUnavailable || (model.englishSuggestions.isEmpty && !model.englishHasUndo)"
        ] {
            XCTAssertTrue(shelf.contains(guardrail), "Keep the existing safety/accessibility contract: \(guardrail)")
        }
        let choices = try XCTUnwrap(shelf.range(of: "                if model.englishCanReplace {"))
        XCTAssertTrue(shelf[..<choices.lowerBound].contains("if model.englishHasUndo, let original = model.englishOriginal {"),
                      "Undo must remain outside the replacement-permission guard")
        XCTAssertTrue(shelf.contains("if model.englishCanReplace {\n                    HStack(spacing: 0) {\n                        ForEach(model.englishSuggestions.indices, id: \\.self)"),
                      "Unavailable suggestions must leave the view, not remain disabled chips")
        XCTAssertFalse(shelf.contains("Suggestions only"))
    }

    func testControllerFitsActual44PointEnglishRowAndShowsAutocorrectionOnlyForImmediateUndo() throws {
        let text = try controllerSource()
        let start = try XCTUnwrap(text.range(of: "        let conversionVisible ="))
        let end = try XCTUnwrap(text.range(of: "        let metrics =", range: start.upperBound..<text.endIndex))
        let visibility = text[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(visibility.contains("language.preferences.effectiveEnglishSuggestions || model.englishHasUndo"))
        XCTAssertFalse(visibility.contains("englishAutocorrection"), "Autocorrection alone must not create an empty shelf")
        XCTAssertTrue(visibility.contains("let prefersCompactShelf = language.mode == .direct ||"))
        XCTAssertTrue(text.contains("prefersCompactShelf: prefersCompactShelf"))
        XCTAssertTrue(text.contains("sceneHeight: usesCompositionLayout ? nil : sceneSize?.height"),
                      "Removing an idle autocorrection shelf must not change the existing normal-key metric")
        XCTAssertTrue(text.contains("applyKeyboardHeight(usesCompositionLayout ? compositionPlan.requestedHeight : metrics.height"))
        XCTAssertTrue(text.contains("normalKeyHeight: usesCompositionLayout ? compositionPlan.mergeNormalKeyHeight : metrics.typingKeyHeight"))
        XCTAssertTrue(text.contains("if undoAvailabilityChanged { updateKeyboardHeight() }"),
                      "Actual immediate Undo changes must renegotiate the optional shelf")
    }
}
#endif
