#if os(macOS)
import Foundation
import XCTest

/// Source wiring only: the package cannot render the keyboard extension's SwiftUI.
/// Runtime blur, alignment and overflow still require Simulator verification.
final class KeyboardConversionViewsSourceTests: XCTestCase {
    private func source(_ relativePath: String = "Keyboard/KeyboardConversionViews.swift") throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath),
                          encoding: .utf8)
    }

    /// Extract a complete source block so guards cannot pass on an unrelated sibling.
    private func block(in text: String, startingAt marker: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: marker))
        let opening = try XCTUnwrap(text[start.lowerBound...].firstIndex(of: "{"))
        var cursor = text.index(after: opening)
        var depth = 1
        while cursor < text.endIndex && depth > 0 {
            if text[cursor] == "{" { depth += 1 }
            if text[cursor] == "}" { depth -= 1 }
            cursor = text.index(after: cursor)
        }
        XCTAssertEqual(depth, 0)
        return String(text[start.lowerBound..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // These guards inspect conditional source structure, not a rendered view or AX tree.
    func testLoadingReplacesTypingInExclusiveContentBranchRatherThanHidingLiveKeys() throws {
        let text = try source("Keyboard/KeyboardViewController.swift")
        let viewStart = try XCTUnwrap(text.range(of: "private struct UnicodeKeyboardView: View {"))
        let bodyEnd = try XCTUnwrap(text.range(of: "    @ViewBuilder private var toolbar: some View {",
                                              range: viewStart.upperBound..<text.endIndex))
        let body = String(text[viewStart.upperBound..<bodyEnd.lowerBound])
        let contentStart = try XCTUnwrap(body.range(of: "                ZStack {"))
        let contentEnd = try XCTUnwrap(body.range(of: "                .frame(maxWidth: .infinity, maxHeight: .infinity)",
                                                 range: contentStart.upperBound..<body.endIndex))
        let content = body[contentStart.lowerBound..<contentEnd.lowerBound]
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertEqual(content, """
        ZStack {
        if model.finishingConversion {
        finishConversionPanel
        } else if model.expandedConversion {
        expandedConversionPanel
        } else if model.showsUnicode {
        unicodeContent
        } else if isConversionLoading {
        conversionLoadingPanel
        } else if needsConversionRecovery {
        conversionRecoveryPanel
        } else {
        typingContent
        }
        }
        """, "Loading must precede typing in the same exclusive branch, not cover or dim mounted normal keys")
        let liveTypingReference = try NSRegularExpression(pattern: #"\btypingContent\b"#)
        XCTAssertEqual(liveTypingReference.numberOfMatches(in: body, range: NSRange(body.startIndex..., in: body)), 1,
                       "No sibling/overlay copy of the normal typing subtree may remain mounted; inset helper names are not live keys")
        XCTAssertFalse(body.contains("KeyboardTypingView("))
        XCTAssertTrue(text.contains("private var isConversionLoading: Bool {\n        language.mode != .direct && language.isLoading\n    }"),
                      "Only non-direct activation blocks typing; the observed loading flag restores it when ready")
    }

    func testLoadingPanelKeepsEscapeAndFooterSwitchingWithoutDuplicateShelf() throws {
        let text = try source("Keyboard/KeyboardViewController.swift")
        let start = try XCTUnwrap(text.range(of: "    private var conversionLoadingPanel: some View {"))
        let end = try XCTUnwrap(text.range(of: "    private var conversionRecoveryPanel: some View {",
                                          range: start.upperBound..<text.endIndex))
        let panel = text[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(panel.contains("ScrollView {"), "Short-height hosts can scroll to the escape action")
        XCTAssertTrue(panel.contains("Text(\"Loading language…\")"))
        XCTAssertTrue(panel.contains("Button(\"Switch to Direct Typing\") { controller?.switchToDirectTyping() }"))
        XCTAssertTrue(panel.contains(".frame(minHeight: 44)"))
        XCTAssertTrue(panel.contains(".accessibilityIdentifier(\"keyboard.conversion.loading\")"))
        for liveKeySource in ["typingContent", "KeyboardTypingView", "KeyboardTouchKey", "KeyboardVariantKey"] {
            XCTAssertFalse(panel.contains(liveKeySource))
        }
        let shelfGuard = try block(in: text, startingAt: "    private var showsCompositionShelf: Bool {")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(shelfGuard, "private var showsCompositionShelf: Bool { !model.showsUnicode && !model.expandedConversion && !model.finishingConversion && (language.mode != .direct || LanguageInputSettings.englishAssistanceAvailable) && ((language.mode == .koreanTwoSetHangul && unreadableNotice == nil) || (!isConversionLoading && !needsConversionRecovery)) && model.compositionShelfHeight > 0 }",
                       "Loading and recovery exclude downloaded-language shelves; local Hangul keeps its existing shelf")
        let shelfBranch = try block(in: text, startingAt: "                if showsCompositionShelf {")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(shelfBranch, "if showsCompositionShelf { if showsEnglishShelf { englishShelf } else { conversionShelf Color.clear.frame(height: model.usesPhonePortraitGeometry ? 0 : 4).accessibilityHidden(true) } }",
                       "Both shelves must remain inside the shared exclusion guard, not duplicate loading status")
        XCTAssertTrue(text.contains("controls\n                    .allowsHitTesting(!model.finishingConversion && !model.expandedConversion)\n                    .accessibilityHidden(model.finishingConversion || model.expandedConversion)"),
                      "Loading alone must not disable the existing guarded space/language-switching footer")
        XCTAssertTrue(text.contains("preservesNormalKeySize: language.mode != .direct ||"),
                      "Ready conversion typing retains the existing normal-size key policy")
    }

    func testLanguagesShowsGeneralFullAccessRequirementWithExactCopyNearInputMode() throws {
        let text = try source("App/LanguagesView.swift")
        let inputMode = try XCTUnwrap(text.range(of: "Section(\"Input Mode\")"))
        let infoReference = try XCTUnwrap(text.range(of: "            infoSection", range: inputMode.upperBound..<text.endIndex))
        let downloads = try XCTUnwrap(text.range(of: "                if model.catalog == nil {"))
        XCTAssertLessThan(infoReference.lowerBound, downloads.lowerBound)
        let info = try block(in: text, startingAt: "    private var infoSection: some View {")
        XCTAssertTrue(info.contains("Text(\"Full Access required\").font(.headline)"))
        XCTAssertTrue(info.contains("Text(\"Allow Full Access so the keyboard can read downloaded language files shared by the app. Your typing stays on this device. Direct Typing works without Full Access.\")"))
        XCTAssertTrue(info.contains(".font(.footnote)"))
        XCTAssertTrue(info.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(info.contains("Button("), "Guidance does not request permission or alter selection")
        XCTAssertFalse(text.contains("hasFullAccess"), "The containing app must not invent the keyboard’s current permission state")
        XCTAssertFalse(text.contains("Downloaded-file access with Full Access off and on still needs device verification."))
        XCTAssertTrue(text.contains("Japanese and Mandarin downloaded language files require Full Access in the keyboard."))
        XCTAssertTrue(text.contains("Conversion uses local data; the containing app contacts the named source hosts only to download resources. The keyboard doesn’t download resources."))
        XCTAssertTrue(text.contains("Downloading and turning on are separate choices. The keyboard opens in the input mode you select here or with the space bar, and the two stay in sync. Without Full Access, it opens in Direct Typing."))
        XCTAssertTrue(text.contains("Label(\"Keyboard Opens in This Mode\", systemImage: \"checkmark\")"))
        XCTAssertFalse(text.contains("session-only"), "The selected mode is remembered and shared with the keyboard")
    }

    func testFullAccessRecoveryHelpIsMissingResourceCJKOnlyAndKeepsActualErrorAndDirectEscape() throws {
        let text = try source("Keyboard/KeyboardViewController.swift")
        let panel = try block(in: text, startingAt: "    private var conversionRecoveryPanel: some View {")
        let help = try block(in: panel, startingAt: "                if language.status == .missingResources,")
        XCTAssertTrue(help.hasPrefix("if language.status == .missingResources,\n                   language.mode == .japaneseRomaji || language.mode == .mandarinPinyin {"),
                      "Direct Typing, unsupported Korean, and non-resource failures must not receive this help")
        XCTAssertTrue(help.contains("Text(\"Full Access required\")"))
        let shortHelp = "Text(\"Allow Full Access to use downloaded languages. Direct Typing is still available.\")"
        XCTAssertTrue(help.contains(shortHelp))
        XCTAssertTrue(help.contains("Text(\"The keyboard needs Full Access to read language files shared locally by Uniboard.\")"))
        XCTAssertTrue(help.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertEqual(text.components(separatedBy: shortHelp).count - 1, 1,
                       "No always-on guidance banner in Direct Typing or unrelated views")
        XCTAssertTrue(panel.contains("ScrollView {"))
        let error = try XCTUnwrap(panel.range(of: "Text(conversionStatusText ?? \"Conversion unavailable.\")"))
        let helpRange = try XCTUnwrap(panel.range(of: help))
        XCTAssertLessThan(error.lowerBound, helpRange.lowerBound, "Keep the actual resource error; permission is a general requirement, not a diagnosis")
        let escape = try XCTUnwrap(panel.range(of: "Button(\"Switch to Direct Typing\") { controller?.switchToDirectTyping() }"))
        XCTAssertLessThan(helpRange.upperBound, escape.lowerBound, "The escape must remain outside the CJK-only help condition")
        XCTAssertTrue(panel.contains(".accessibilityIdentifier(\"keyboard.conversion.switchToDirect\")"))
        XCTAssertTrue(panel.contains("Button(\"Keep Typed Text\")"))
        XCTAssertTrue(panel.contains("Button(\"Cancel Conversion\")"))
    }

    func testEveryConversionScrollDisablesAutomaticEdgeEffects() throws {
        let text = try source()
        let pattern = try NSRegularExpression(pattern: #"\bScrollView(?:\([^\n]*\))?\s*\{"#)
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertFalse(matches.isEmpty, "Inspect every actual ScrollView block, including the new full-value literal scroll")
        for match in matches {
            let range = try XCTUnwrap(Range(match.range, in: text))
            var cursor = range.upperBound
            var depth = 1
            // These view bodies contain balanced braces, including interpolation.
            while cursor < text.endIndex && depth > 0 {
                if text[cursor] == "{" { depth += 1 }
                if text[cursor] == "}" { depth -= 1 }
                cursor = text.index(after: cursor)
            }
            XCTAssertEqual(depth, 0)
            let modifiers = text[cursor...].components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .prefix { $0.isEmpty || $0.hasPrefix(".") }
                .joined(separator: "\n")
            XCTAssertTrue(modifiers.contains(".conversionUnmaskedScrollEdges()"),
                          "Every scroll must opt out directly, including short-height recovery")
        }
        XCTAssertTrue(text.contains("private extension View {"))
        XCTAssertTrue(text.contains("if #available(iOS 26.0, *) { scrollEdgeEffectHidden() }\n        else { self }"),
                      "Preserve the iOS 17 minimum and leave older scroll rendering unchanged")
    }

    func testRegularCaptionKeepsIntrinsicShortNameAndControllerMeasuresItsHalfLineFit() throws {
        let text = try source()
        let captionStart = try XCTUnwrap(text.range(of: "                    Text(KeyboardConversionShelfMetrics.caption(for: display.mode))"))
        let preeditStart = try XCTUnwrap(text.range(of: "                    GeometryReader { viewport in",
                                                   range: captionStart.upperBound..<text.endIndex))
        let caption = text[captionStart.lowerBound..<preeditStart.lowerBound]
        XCTAssertTrue(caption.contains(".font(.system(size: captionSize))"))
        XCTAssertTrue(caption.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(caption.contains(".accessibilityIdentifier(\"keyboard.conversion.modeCaption\")"))
        XCTAssertFalse(caption.contains(".frame(maxWidth:"), "The caption must reserve its intrinsic width")
        XCTAssertFalse(text.contains(".layoutPriority(1)"), "The unfinished-text GeometryReader must not collapse the caption")
        for name in ["Japanese", "Mandarin", "Korean"] {
            XCTAssertTrue(text.contains("return \"\(name)\""))
        }
        XCTAssertFalse(text.contains("Mandarin Chinese — Pinyin"))
        XCTAssertTrue(text.contains("@ScaledMetric(relativeTo: .footnote) private var captionSize = 13.0"))
        XCTAssertTrue(text.contains("UIFontMetrics(forTextStyle: .footnote).scaledFont("))
        XCTAssertTrue(text.contains("for: UIFont.systemFont(ofSize: 13), compatibleWith: captionTraits"))
        XCTAssertTrue(text.contains("captionWidth: width, availableLineWidth: containerWidth - 16"))
        let controller = try source("Keyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("containerWidth: max(0, view.bounds.width - 16), traits: traitCollection"))
        XCTAssertTrue(controller.contains("prefersCompactShelf: prefersCompactShelf"))
        // Half-line arithmetic is exercised by KeyboardCompositionLayoutTests.
        // This test proves wiring only, not UIFont rendering or actual shelf bounds.
    }

    func testRegularIdleShelfIsBlankAndStatusRemainsInCandidateRow() throws {
        let text = try source()
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        let regular = try block(in: shelf, startingAt: "            if !compact {")
        XCTAssertTrue(regular.contains("Text(display.preedit.isEmpty ? display.rawInput : display.preedit)"))
        XCTAssertFalse(regular.contains("Type to convert"))
        XCTAssertTrue(regular.contains(".frame(height: 30)\n                .opacity(display.rawInput.isEmpty ? 0 : 1)\n                .accessibilityHidden(display.rawInput.isEmpty)\n                .allowsHitTesting(!display.rawInput.isEmpty)"),
                      "The entire caption/preedit row stays laid out but is invisible and inert for every idle state")
        XCTAssertTrue(regular.contains(".accessibilityLabel(\"Unfinished text\")"))
        XCTAssertTrue(regular.contains(".accessibilityValue(conversionUnfinishedValue(rawInput: display.rawInput, preedit: display.preedit))"),
                      "Active typing retains existing unfinished-text accessibility")
        let strip = try block(in: text, startingAt: "private struct ConversionCandidateStrip: View {")
        XCTAssertTrue(strip.contains("if let message = display.statusText ?? (display.rawInput.isEmpty ? nil : (display.outputs.isEmpty ? \"No matching conversion\" : nil)) {"),
                      "Status keeps priority; no shelf retains an idle candidate prompt; active no-match copy is unchanged")
    }

    func testOrdinaryIdleShelvesAreInertEverywhereButStatusStaysAccessible() throws {
        let text = try source()
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        XCTAssertTrue(shelf.contains("let hidesIdleShelf = display.rawInput.isEmpty && display.statusText == nil\n        if display.mode == .koreanTwoSetHangul {"),
                      "Ordinary idle is hidden for every shelf, including compact height fallback; status and typing stay accessible")
        let hangul = try block(in: shelf, startingAt: "        if display.mode == .koreanTwoSetHangul {")
        XCTAssertTrue(hangul.contains(".overlay(alignment: .bottom) { KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8) }\n                .accessibilityHidden(hidesIdleShelf)\n                .allowsHitTesting(!hidesIdleShelf)"),
                      "Keep the Hangul hairline while hiding the ordinary idle accessibility/touch region")
        XCTAssertTrue(shelf.contains(".accessibilityLabel(\"Conversion Choices\")\n        .accessibilityHidden(hidesIdleShelf)\n        .allowsHitTesting(!hidesIdleShelf)"))
        XCTAssertTrue(shelf.contains(".overlay(alignment: .bottom) {\n            KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8)\n        }"))
        let word = try block(in: text, startingAt: "private struct KoreanHangulWordRow: View {")
        XCTAssertTrue(word.contains("Text(display.statusText ?? (display.rawInput.isEmpty ? \"\" : \"Converting…\"))"),
                      "Two-Set idle is blank without status and displays only status when supplied")
        XCTAssertFalse(word.contains("\"Two-Set Hangul\""))
    }

    func testRegularIdleExpansionHidesDividerAndDisablesButtonWithoutRemovingItsSlot() throws {
        let text = try source()
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        XCTAssertTrue(shelf.contains("let hidesExpansion = !compact && display.rawInput.isEmpty"),
                      "Use the touch-frozen display, not live raw input; regular typing keeps expansion and compact idle uses its separate status-only branch")
        XCTAssertTrue(shelf.contains("ConversionCandidateStrip(display: display, touching: touching, compact: compact)\n                    KeyboardCandidateDivider()\n                        .opacity(hidesExpansion ? 0 : 1)\n                    Button(action: onExpand) {"),
                      "The regular divider and expansion control keep their reserved slots")
        let chevron = try XCTUnwrap(shelf.range(of: "Image(systemName: \"chevron.down\")"))
        let trailingControl = String(shelf[chevron.lowerBound...])
        XCTAssertTrue(trailingControl.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(trailingControl.contains(".accessibilityAction { onExpand() }\n                    .opacity(hidesExpansion ? 0 : 1)\n                    .disabled(hidesExpansion)\n                    .accessibilityHidden(hidesExpansion)"),
                      "An invisible More Choices control must neither respond nor appear in VoiceOver")
    }

    func testIdleCleanupPreservesShelfFitAndCompactAndHangulBranches() throws {
        let text = try source()
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        XCTAssertTrue(shelf.contains("private var compact: Bool { height < 74 }"))
        XCTAssertTrue(shelf.contains(".frame(height: 30)"))
        XCTAssertTrue(shelf.contains(".frame(height: compact ? 44 : 74)"))
        let compact = try block(in: shelf, startingAt: "                    if compact {")
        XCTAssertTrue(compact.contains("compactUnfinishedButton(display, touching: touching)"))
        XCTAssertTrue(compact.contains("KeyboardCandidateDivider()"))
        XCTAssertFalse(compact.contains("Image(systemName:"))
        XCTAssertFalse(compact.contains("hidesExpansion"))
        let hangul = try block(in: shelf, startingAt: "        if display.mode == .koreanTwoSetHangul {")
        XCTAssertTrue(hangul.contains("KoreanHangulWordRow(display: display, touching: touching)"))
        XCTAssertTrue(hangul.contains(".frame(height: 44)"))
        XCTAssertFalse(hangul.contains("hidesExpansion"))
    }

    func testCompactIdleHasOnlyStatusAndNoExpansionOrPrompt() throws {
        let text = try source()
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        let idle = try block(in: shelf, startingAt: "                if compact && display.rawInput.isEmpty {")
        XCTAssertTrue(idle.contains("Text(display.statusText ?? \"\")"))
        XCTAssertTrue(idle.contains(".font(.footnote)"))
        XCTAssertTrue(idle.contains(".foregroundStyle(KeyboardCandidateInk.secondary)"))
        XCTAssertTrue(idle.contains(".padding(.leading, 12)"))
        XCTAssertTrue(idle.contains(".frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)"))
        for actionable in ["Button(", "KeyboardCandidateDivider", "ConversionCandidateStrip", "compactUnfinishedButton", "Image("] {
            XCTAssertFalse(idle.contains(actionable), "Compact idle/status must not mount unfinished text, candidates or More")
        }
        XCTAssertTrue(shelf.contains(idle + " else {"), "Status-only idle must be exclusive with the composing controls")
        XCTAssertFalse(shelf.contains("Type to convert"))
        let strip = try block(in: text, startingAt: "private struct ConversionCandidateStrip: View {")
        XCTAssertFalse(strip.contains("Type to convert"))
        XCTAssertFalse(shelf.contains("text.bubble"))
        XCTAssertTrue(shelf.contains(".frame(height: compact ? 44 : 74)"))
        XCTAssertTrue(shelf.contains("KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8)"))
    }

    func testCompactPreeditMeasuresIntrinsicViewportAndKeepsOneAccessibleExpandButton() throws {
        let text = try source()
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        let preedit = try block(in: shelf, startingAt: "    private func compactUnfinishedButton(")
        XCTAssertTrue(shelf.contains("@ScaledMetric(relativeTo: .body) private var preeditSize = 17.0"))
        XCTAssertTrue(preedit.contains("let unfinished = display.preedit.isEmpty ? display.rawInput : display.preedit"))
        XCTAssertTrue(preedit.contains("let textWidth = ceil((unfinished as NSString).size(withAttributes:"))
        XCTAssertTrue(preedit.contains(".font: UIFont.systemFont(ofSize: preeditSize)"))
        XCTAssertTrue(preedit.contains("let viewportWidth = min(160, max(44, textWidth + 12 + 8))"),
                      "Clamp measured text plus both insets, not a greedy ScrollView proposal")
        let scroll = try block(in: preedit, startingAt: "            ScrollView(.horizontal) {")
        XCTAssertTrue(scroll.contains("Button(action: onExpand) {"))
        XCTAssertEqual(preedit.components(separatedBy: "Button(action:").count - 1, 1)
        XCTAssertTrue(scroll.contains("Text(verbatim: unfinished)"))
        XCTAssertTrue(scroll.contains(".font(.system(size: preeditSize))"))
        XCTAssertTrue(scroll.contains(".foregroundStyle(KeyboardCandidateInk.secondary)"))
        XCTAssertTrue(scroll.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(scroll.contains(".padding(.leading, 12)\n                        .padding(.trailing, 8)"))
        XCTAssertTrue(scroll.contains(".frame(minWidth: viewportWidth, minHeight: 44, alignment: .leading)"))
        XCTAssertTrue(scroll.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(scroll.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(scroll.contains(".accessibilityLabel(\"Unfinished text\")"))
        XCTAssertTrue(scroll.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(scroll.contains(".accessibilityValue(conversionUnfinishedValue(rawInput: display.rawInput, preedit: display.preedit))"))
        XCTAssertTrue(scroll.contains(".accessibilityHint(\"Opens Conversion Choices\")"))
        XCTAssertFalse(preedit.contains("caption"))
        XCTAssertFalse(preedit.contains(".frame(maxWidth:"))
        XCTAssertTrue(preedit.contains(".defaultScrollAnchor(.trailing)"))
        XCTAssertTrue(preedit.contains(".scrollIndicators(.hidden)\n            .frame(width: viewportWidth, height: 44)"),
                      "The scroll viewport itself, not just its content, must have the measured width")
        XCTAssertTrue(preedit.contains(".onChange(of: display.generation) { _, _ in\n                if !touching { scroll.scrollTo(\"compact-preedit\", anchor: .trailing) }"))
        XCTAssertFalse(preedit.contains("DragGesture"))
        XCTAssertFalse(preedit.contains("onTapGesture"))
        XCTAssertTrue(shelf.contains("shelfContent(display, touching: touching)"))
        // Source contracts only: native short/long preedit bounds, scrolling and
        // drag-versus-tap behavior must still be verified in the extension.
    }

    func testShelfLiteralButtonDisplaysOnlyVerbatimInputAndPreservesAccessibilityExplanation() throws {
        let text = try source()
        let strip = try block(in: text, startingAt: "private struct ConversionCandidateStrip: View {")
        let literal = try block(in: strip, startingAt: "private func literalButton(")
        let button = try block(in: literal, startingAt: "Button(action: action) {")
        let normalizedButton = button.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        XCTAssertEqual(normalizedButton, """
        Button(action: action) {
        Text(verbatim: rawInput)
        .font(.system(size: outputSize, weight: .regular))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(minWidth: 44, minHeight: 44, maxHeight: 44)
        .contentShape(Rectangle())
        }
        """, "Inspect the complete Button label: exact raw text only, no prefix, quotes, width cap, card or truncation")
        XCTAssertTrue(strip.contains("@ScaledMetric(relativeTo: .title3) private var outputSize = 20.0"))
        XCTAssertTrue(strip.contains("literalButton(rawInput: display.rawInput, action: display.onLiteral)"))
        XCTAssertTrue(literal.contains(#".accessibilityLabel("Insert exactly as typed: \(rawInput)")"#))
        XCTAssertTrue(literal.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(literal.contains(".accessibilityValue(rawInput)"))
        XCTAssertTrue(literal.contains(".accessibilityHint(\"Inserts the exact typed text\")"))
    }

    func testLiteralFirstAndNonliteralOrderDefaultAndOriginalTokenWiringRemainIntact() throws {
        let text = try source()
        let snapshot = try block(in: text, startingAt: "private struct ConversionDisplaySnapshot {")
        XCTAssertTrue(snapshot.contains("rawInput.isEmpty ? [] : candidates.filter { $0.source != .literal }"))
        XCTAssertTrue(snapshot.contains("raw: Array(rawInput.utf8), preedit: Array(preedit.utf8)"),
                      "Presentation generation identity must distinguish original scalar sequences")
        let strip = try block(in: text, startingAt: "private struct ConversionCandidateStrip: View {")
        let literal = try XCTUnwrap(strip.range(of: "literalButton(rawInput: display.rawInput, action: display.onLiteral)"))
        let converted = try XCTUnwrap(strip.range(of: "ForEach(display.outputs)"))
        XCTAssertLessThan(literal.lowerBound, converted.lowerBound)
        XCTAssertTrue(strip.contains("pending: candidate.id == display.outputs.first?.id"))
        XCTAssertTrue(strip.contains("candidate: candidate, token: display.token"))
        XCTAssertTrue(strip.contains("onChoose: display.onChoose"))
        XCTAssertFalse(strip.contains(".sorted"))
        let candidate = try block(in: text, startingAt: "private struct ConversionCandidateButton: View {")
        XCTAssertTrue(candidate.contains("Button { [candidate, token, onChoose] in\n            onChoose(candidate.id, token)"))
        XCTAssertTrue(candidate.contains(#".accessibilityLabel("Insert \(candidate.output)")"#))
        XCTAssertTrue(candidate.contains(#".accessibilityValue([annotation, pending ? "Pending" : nil]"#))
        XCTAssertTrue(candidate.contains(".accessibilityAddTraits(.isButton)"),
                      "Ignoring label children must not turn an actionable output into an AX generic element")
        XCTAssertTrue(candidate.contains(".accessibilityAddTraits(pending ? .isSelected : [])"))
        for source in ["Hiragana", "Katakana", "My Words"] {
            XCTAssertTrue(candidate.contains("return \"\(source)\""))
        }
        XCTAssertFalse(candidate.contains("Text(annotation)"))
        XCTAssertFalse(candidate.contains("Text(\"Pending\")"))
        let controller = try source("Keyboard/KeyboardViewController.swift")
        let shelf = try block(in: controller, startingAt: "    private var conversionShelf: some View {")
        XCTAssertTrue(shelf.contains("let token = language.state.token"))
        XCTAssertTrue(shelf.contains("onChoose: { controller?.chooseConversion($0, token: $1) }"))
        XCTAssertTrue(shelf.contains("onLiteral: { controller?.keepRomanLetters(token: token) }"))
    }

    func testFlatCandidateTypographyDividersAndPressFeedbackHaveNoPersistentCards() throws {
        let text = try source()
        let label = try block(in: text, startingAt: "struct KeyboardCandidateText: View {")
        XCTAssertTrue(label.contains("@ScaledMetric(relativeTo: .title3) private var outputSize = 20.0"))
        XCTAssertTrue(label.contains("Text(verbatim: output)"))
        XCTAssertTrue(label.contains("weight: pending ? .semibold : .regular"))
        XCTAssertTrue(label.contains(".fixedSize(horizontal: !expanded, vertical: expanded)"))
        XCTAssertTrue(label.contains(".padding(.horizontal, 12)"))
        XCTAssertTrue(label.contains("maxWidth: expanded ? .infinity : nil"))
        XCTAssertTrue(label.contains("minHeight: 44, maxHeight: expanded ? nil : 44"))
        XCTAssertTrue(label.contains(".foregroundStyle(Color(uiColor: .label))"))
        let divider = try block(in: text, startingAt: "struct KeyboardCandidateDivider: View {")
        XCTAssertTrue(divider.contains("@Environment(\\.displayScale)"))
        XCTAssertTrue(divider.contains("width: vertical ? 1 / displayScale : nil"))
        XCTAssertTrue(divider.contains("height: vertical ? 20 : 1 / displayScale"))
        XCTAssertTrue(divider.contains(".accessibilityHidden(true)"))
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        XCTAssertTrue(shelf.contains("ConversionCandidateStrip(display: display, touching: touching, compact: compact)\n                    KeyboardCandidateDivider()\n                        .opacity(hidesExpansion ? 0 : 1)\n                    Button(action: onExpand)"))
        XCTAssertTrue(shelf.contains(".font(.system(size: 17, weight: .medium))"))
        XCTAssertTrue(shelf.contains(".frame(width: 44, height: 44)"))
        let strip = try block(in: text, startingAt: "private struct ConversionCandidateStrip: View {")
        XCTAssertTrue(strip.contains("HStack(spacing: 0)"))
        XCTAssertTrue(strip.contains("ForEach(display.outputs) { candidate in\n                                KeyboardCandidateDivider()"))
        let pressed = try block(in: text, startingAt: "struct KeyboardCandidateButtonStyle: ButtonStyle {")
        XCTAssertTrue(pressed.contains("if configuration.isPressed {"))
        XCTAssertTrue(pressed.contains("Color.white.opacity(0.10) : Color.black.opacity(0.08)"))
        XCTAssertFalse(pressed.contains("RoundedRectangle"))
        for marker in ["struct KeyboardConversionShelf: View {", "struct KeyboardExpandedConversionView: View {",
                       "private struct ConversionCandidateButton: View {", "private struct ConversionCandidateStrip: View {"] {
            let area = try block(in: text, startingAt: marker)
            for forbidden in ["RoundedRectangle", "strokeBorder", "tertiarySystemFill", "secondarySystemGroupedBackground", ".material", "minimumScaleFactor", "maxWidth: 240", "maxWidth: 280"] {
                XCTAssertFalse(area.contains(forbidden), "No candidate card/cap/second backing in \(marker): \(forbidden)")
            }
        }
    }

    func testCandidateInkIsSolidAndScopedAwayFromGenericRecovery() throws {
        let text = try source()
        let ink = try block(in: text, startingAt: "enum KeyboardCandidateInk {")
        XCTAssertTrue(ink.contains("traits.userInterfaceStyle == .dark"))
        XCTAssertTrue(ink.contains("UIColor(red: 84.0 / 255, green: 84.0 / 255, blue: 93.0 / 255, alpha: 1)"))
        XCTAssertTrue(ink.contains("UIColor(red: 177.0 / 255, green: 177.0 / 255, blue: 186.0 / 255, alpha: 1)"))
        XCTAssertTrue(ink.contains("UIColor(red: 138.0 / 255, green: 142.0 / 255, blue: 152.0 / 255, alpha: 1)"))
        XCTAssertTrue(ink.contains("UIColor(red: 99.0 / 255, green: 99.0 / 255, blue: 107.0 / 255, alpha: 1)"))
        XCTAssertFalse(ink.contains(".opacity("))
        let informative = try block(in: text, startingAt: "enum KeyboardLanguageInformativeInk {")
        XCTAssertTrue(informative.contains("UIColor(red: 98.0 / 255, green: 98.0 / 255, blue: 107.0 / 255, alpha: 1)"))
        let finish = try block(in: text, startingAt: "struct KeyboardFinishConversionView: View {")
        XCTAssertTrue(finish.contains("KeyboardLanguageInformativeInk.secondary"))
        XCTAssertFalse(finish.contains("KeyboardCandidateInk.secondary"))
        for marker in ["struct KeyboardConversionShelf: View {", "struct KeyboardExpandedConversionView: View {", "private struct ConversionCandidateStrip: View {"] {
            let area = try block(in: text, startingAt: marker)
            XCTAssertTrue(area.contains("KeyboardCandidateInk.secondary"))
            XCTAssertFalse(area.contains("KeyboardLanguageInformativeInk.secondary"))
        }
    }

    func testExpandedGridWrapsAndPinsScrollableVerbatimLiteralSeparatelyFromCancel() throws {
        let text = try source()
        let expanded = try block(in: text, startingAt: "struct KeyboardExpandedConversionView: View {")
        XCTAssertTrue(expanded.contains("!dynamicTypeSize.isAccessibilitySize && geometry.size.width >= 264"))
        XCTAssertTrue(expanded.contains("GridItem(.flexible(minimum: 120), spacing: 8)"))
        XCTAssertTrue(expanded.contains("count: twoColumns ? 2 : 1"))
        XCTAssertTrue(expanded.contains("LazyVGrid(columns: columns, alignment: .leading, spacing: 0)"))
        XCTAssertTrue(expanded.contains("pending: candidate.id == display.outputs.first?.id"))
        XCTAssertTrue(expanded.contains("expanded: true, onChoose: display.onChoose"))
        XCTAssertTrue(expanded.contains("focused = display.outputs.first.map { .candidate($0.id) } ?? .preedit"))
        XCTAssertTrue(expanded.contains("ViewThatFits(in: .vertical)"), "Only the local literal-fit alternative may depend on ideal text height")
        XCTAssertTrue(expanded.contains("ScrollView {\n                    VStack(spacing: 0)"), "Keep the whole-panel short-height escape")
        let candidate = try block(in: text, startingAt: "private struct ConversionCandidateButton: View {")
        XCTAssertTrue(candidate.contains("if expanded {\n                        KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8)"))
        let recovery = try block(in: expanded, startingAt: "private func recoveryActions(")
        let region = try block(in: expanded, startingAt: "private func literalRegion(")
        let scroll = try block(in: region, startingAt: "ScrollView(.vertical) {")
        XCTAssertTrue(scroll.contains("literalButton(rawInput: display.rawInput, action: display.onLiteral)"))
        XCTAssertFalse(scroll.contains("Cancel Conversion"), "Cancel must stay reachable outside the long-literal scroll")
        XCTAssertTrue(recovery.contains("literalRegion(display, height: literalHeight)"))
        XCTAssertTrue(region.contains(".frame(height: height)"))
        XCTAssertTrue(recovery.contains(".frame(height: cancelHeight)"))
        XCTAssertTrue(recovery.contains("ConversionPanelAction(title: \"Cancel Conversion\", action: display.onCancel, foreground: Self.cancelInk)"))
        let literal = try block(in: expanded, startingAt: "private func literalButton(")
        let button = try block(in: literal, startingAt: "Button(action: action) {")
        XCTAssertTrue(button.contains("Text(verbatim: rawInput)"))
        XCTAssertTrue(button.contains(".font(.system(size: outputSize, weight: .regular))"))
        XCTAssertTrue(button.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(button.contains("conversionLiteralName"))
        XCTAssertFalse(button.contains("ConversionPanelAction"))
        XCTAssertFalse(literal.contains(".accessibilityLabel("), "Inner fit alternatives must not export duplicate AX labels")
        XCTAssertTrue(region.contains(#".accessibilityLabel("Insert exactly as typed: \(display.rawInput)")"#))
        XCTAssertTrue(region.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(region.contains(".accessibilityValue(display.rawInput)"))
        XCTAssertTrue(region.contains(".accessibilityHint(\"Inserts the exact typed text\")"))
        XCTAssertTrue(expanded.contains("Button(action: onClose)"))
        XCTAssertTrue(expanded.contains(#"Text("Then insert \(queuedPunctuation)")"#))
    }

    func testOnlyExpandedCancelUsesApprovedLightInkAndKeepsDarkSystemBlue() throws {
        let text = try source()
        let expanded = try block(in: text, startingAt: "struct KeyboardExpandedConversionView: View {")
        let ink = try block(in: expanded, startingAt: "private static let cancelInk =")
        XCTAssertTrue(ink.contains("traits.userInterfaceStyle == .dark"))
        XCTAssertTrue(ink.contains("UIColor.systemBlue.resolvedColor(with: traits)"))
        XCTAssertTrue(ink.contains("UIColor(red: 0, green: 87.0 / 255, blue: 184.0 / 255, alpha: 1)"))
        XCTAssertFalse(ink.contains(".opacity("))
        let recovery = try block(in: expanded, startingAt: "private func recoveryActions(")
        XCTAssertTrue(recovery.contains("ConversionPanelAction(title: \"Cancel Conversion\", action: display.onCancel, foreground: Self.cancelInk)"))
        XCTAssertEqual(text.components(separatedBy: "foreground: Self.cancelInk").count - 1, 1,
                       "This override must not recolor literal/converted choices, other actions or global tint")
        let panelAction = try block(in: text, startingAt: "private struct ConversionPanelAction: View {")
        XCTAssertTrue(panelAction.contains("var foreground = Color(uiColor: .systemBlue)"), "Generic recovery actions keep their existing default")
        XCTAssertTrue(panelAction.contains(".foregroundStyle(foreground)"))
        let finish = try block(in: text, startingAt: "struct KeyboardFinishConversionView: View {")
        XCTAssertFalse(finish.contains("cancelInk"))
        XCTAssertFalse(finish.contains("foreground:"))
        XCTAssertFalse(expanded.contains(".tint("))
    }

    func testExpandedLiteralExportsOneStableSemanticRegionOutsideItsFitAlternatives() throws {
        let text = try source()
        let expanded = try block(in: text, startingAt: "struct KeyboardExpandedConversionView: View {")
        let region = try block(in: expanded, startingAt: "private func literalRegion(")
        let fit = try block(in: region, startingAt: "ViewThatFits(in: .vertical) {")
        XCTAssertFalse(fit.contains(".accessibilityElement("))
        XCTAssertFalse(fit.contains(".accessibilityAction"))
        XCTAssertTrue(region.contains("VStack(spacing: 0) {\n            ViewThatFits(in: .vertical)"),
                      "A stable region, not a conditional fit child, must own the accessible button")
        let semanticStart = try XCTUnwrap(region.range(of: ".frame(height: height)"))
        let semantics = region[semanticStart.lowerBound...]
        XCTAssertTrue(semantics.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(semantics.contains(#".accessibilityLabel("Insert exactly as typed: \(display.rawInput)")"#))
        XCTAssertTrue(semantics.contains(".accessibilityValue(display.rawInput)"))
        XCTAssertTrue(semantics.contains(".accessibilityHint(\"Inserts the exact typed text\")"))
        XCTAssertTrue(semantics.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(semantics.contains(".disabled(display.rawInput.isEmpty)"))
        let action = try block(in: region, startingAt: ".accessibilityAction {")
        XCTAssertEqual(action.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"), """
        .accessibilityAction {
        guard !display.rawInput.isEmpty else { return }
        display.onLiteral()
        }
        """, "VoiceOver must forward once to the immutable displayed callback, never a current token or candidate guess")
        XCTAssertEqual(expanded.components(separatedBy: "Insert exactly as typed:").count - 1, 1,
                       "Both fit alternatives share exactly one semantic label/action")
        let inner = try block(in: expanded, startingAt: "private func literalButton(")
        XCTAssertFalse(inner.contains(".accessibility"), "The physical inner buttons are ignored by their semantic region")
        XCTAssertTrue(inner.contains("Button(action: action) {"))
        XCTAssertTrue(inner.contains("Text(verbatim: rawInput)"))
    }

    func testImageOnlyMoreAndCloseKeepExplicitButtonSemanticsAndExistingActions() throws {
        let text = try source()
        let shelf = try block(in: text, startingAt: "struct KeyboardConversionShelf: View {")
        XCTAssertTrue(shelf.contains(".accessibilityElement(children: .ignore)\n                    .accessibilityLabel(\"More Choices\")\n                    .accessibilityAddTraits(.isButton)\n                    .accessibilityAction { onExpand() }"))
        let expanded = try block(in: text, startingAt: "struct KeyboardExpandedConversionView: View {")
        let header = try block(in: expanded, startingAt: "private func expandedHeader(")
        XCTAssertTrue(header.contains("Button(action: onClose) {"))
        XCTAssertTrue(header.contains(".accessibilityElement(children: .ignore)\n            .accessibilityLabel(\"Close Conversion Choices\")\n            .accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(header.contains(".accessibilityHint(\"Keeps unfinished text without inserting it\")\n            .accessibilityAction { onClose() }"))
    }

    func testExpandedNormalHeightPinsRecoveryUsingExplicitBudgetsNotCandidateIdealHeight() throws {
        let text = try source()
        let expanded = try block(in: text, startingAt: "struct KeyboardExpandedConversionView: View {")
        let layout = try block(in: expanded, startingAt: "private func expandedContent(")
        XCTAssertFalse(layout.contains("ViewThatFits"),
                       "A long grid's ideal height must not put normal-height literal/Cancel below the viewport")
        XCTAssertTrue(layout.contains("let separatorHeight = 1 / displayScale"))
        XCTAssertTrue(layout.contains("let cancelHeight = cancelActionHeight(width: geometry.size.width)"))
        XCTAssertTrue(layout.contains("let minimumPinnedHeight = 44 * 3 + cancelHeight + separatorHeight"))
        let pinned = try block(in: layout, startingAt: "if geometry.size.height >= minimumPinnedHeight {")
        XCTAssertTrue(pinned.contains("let textRegionBudget = geometry.size.height - cancelHeight - separatorHeight - 44"))
        XCTAssertTrue(pinned.contains("let headerHeight = min(min(max(44, geometry.size.height * 0.24), 100), textRegionBudget - 44)"))
        XCTAssertTrue(pinned.contains("let literalHeight = min(max(44, geometry.size.height * 0.25), textRegionBudget - headerHeight)"))
        XCTAssertTrue(pinned.contains("let gridHeight = geometry.size.height - headerHeight - literalHeight - cancelHeight - separatorHeight"))
        XCTAssertTrue(pinned.contains(".frame(height: gridHeight)"), "Grid gets the remainder, not its ideal content height")
        XCTAssertTrue(pinned.contains(".frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)"))
        let gridScroll = try block(in: pinned, startingAt: "ScrollView {")
        XCTAssertEqual(gridScroll, "ScrollView { choiceContent(display, columns: columns) }")
        let grid = try XCTUnwrap(pinned.range(of: "ScrollView {"))
        let recovery = try XCTUnwrap(pinned.range(of: "recoveryActions(display, literalHeight: literalHeight, cancelHeight: cancelHeight)"))
        XCTAssertLessThan(grid.lowerBound, recovery.lowerBound)
        XCTAssertFalse(gridScroll.contains("recoveryActions"), "Recovery must be a pinned sibling, never part of the grid scroll")
        let short = try block(in: layout, startingAt: "} else {")
        XCTAssertTrue(short.contains("ScrollView {\n                    VStack(spacing: 0)"))
        XCTAssertTrue(short.contains("expandedHeader(display, height: 100)"))
        XCTAssertTrue(short.contains("choiceContent(display, columns: columns)"))
        XCTAssertTrue(short.contains("recoveryActions(display,"))
        let measurement = try block(in: expanded, startingAt: "private func cancelActionHeight(")
        XCTAssertTrue(measurement.contains("width: max(1, width - 40)"))
        XCTAssertTrue(measurement.contains("UIFont.systemFont(ofSize: cancelSize)"))
        XCTAssertTrue(measurement.contains("return max(44, ceil(bounds.height) + 16)"),
                      "Scaled/wrapped Cancel height participates in the short-host threshold")
    }

    func testTouchSnapshotsRetainDisplayedActionsUntilEveryTouchEndsWithoutBlockingScroll() throws {
        let text = try source()
        let snapshot = try block(in: text, startingAt: "private struct ConversionTouchSnapshotView<Content: View>: View {")
        XCTAssertTrue(snapshot.contains("content(displayed, isTouching)"))
        XCTAssertTrue(snapshot.contains(".background(ConversionTouchObserver(onActive: receiveTouch))"))
        XCTAssertTrue(snapshot.contains("newest = latest\n                if !isTouching { displayed = latest }"))
        let release = try block(in: snapshot, startingAt: "private func receiveTouch(")
        XCTAssertTrue(release.contains("DispatchQueue.main.async {"))
        XCTAssertTrue(release.contains("guard touchSequence == sequence else { return }"))
        XCTAssertTrue(release.contains("displayed = newest\n                isTouching = false"))
        let observer = try block(in: text, startingAt: "private final class ConversionTouchRecognizer:")
        XCTAssertTrue(observer.contains("private var activeTouches = Set<ObjectIdentifier>()"))
        XCTAssertTrue(observer.contains("region.bounds.contains(touch.location(in: region))"))
        XCTAssertTrue(observer.contains("cancelsTouchesInView = false"))
        XCTAssertTrue(observer.contains("delaysTouchesBegan = false"))
        XCTAssertTrue(observer.contains("delaysTouchesEnded = false"))
        XCTAssertTrue(observer.contains("canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }"))
        XCTAssertTrue(observer.contains("canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }"))
        XCTAssertTrue(observer.contains("touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { remove(touches) }"))
        let removal = try block(in: observer, startingAt: "private func remove(")
        XCTAssertTrue(removal.contains("activeTouches.subtract(touches.map { ObjectIdentifier($0) })"))
        XCTAssertTrue(removal.contains("if activeTouches.isEmpty {\n            region?.onActive(false)"))
        for marker in ["struct KeyboardConversionShelf: View {", "struct KeyboardExpandedConversionView: View {"] {
            let area = try block(in: text, startingAt: marker)
            XCTAssertTrue(area.contains("ConversionTouchSnapshotView(latest: ConversionDisplaySnapshot("))
            XCTAssertTrue(area.contains("onChoose: onChoose, onLiteral: onLiteral"))
        }
    }

    func testPendingRevealIsGenerationScopedWhollyOutsideOnlyAndNeverASelection() throws {
        let text = try source()
        let strip = try block(in: text, startingAt: "private struct ConversionCandidateStrip: View {")
        XCTAssertTrue(strip.contains(".onChange(of: display.generation)"))
        XCTAssertTrue(strip.contains("revealRequest = generation"))
        XCTAssertTrue(strip.contains("rect: cell.frame(in: .named(viewportSpace))"))
        let reveal = try block(in: strip, startingAt: "private func revealIfNeeded(")
        XCTAssertTrue(reveal.contains("guard !touching, let request, let frame, request == display.generation"))
        XCTAssertTrue(reveal.contains("request == frame.generation, let first = display.outputs.first"))
        XCTAssertTrue(reveal.contains("revealRequest = nil"), "Consume generation once so ordinary scrolling cannot snap back")
        XCTAssertTrue(reveal.contains("if frame.rect.maxX <= 0 || frame.rect.minX >= width {"))
        XCTAssertTrue(reveal.contains("scroll.scrollTo(first.id, anchor: .leading)"))
        XCTAssertFalse(reveal.contains("onChoose"))
        XCTAssertFalse(reveal.contains("onLiteral"))
        XCTAssertFalse(strip.contains("withAnimation"))
    }

    func testTypingGuideDescribesVisibleSpellingRatherThanRemovedLiteralActionLabels() throws {
        let text = try source("App/LanguagesView.swift")
        let guide = try block(in: text, startingAt: "private struct LanguageTypingGuideView: View {")
        let literal = try block(in: guide, startingAt: "Section(\"Literal input and cancel\") {")
        XCTAssertTrue(literal.contains("Text(\"To insert exactly what you typed without conversion, tap that spelling in the choices.\")"))
        let japanese = try block(in: literal, startingAt: "if mode == .japaneseRomaji {")
        XCTAssertTrue(japanese.contains("Text(\"For example, tap nihongo to insert nihongo.\")"))
        XCTAssertTrue(literal.contains("Text(\"Cancel Conversion clears only unfinished text, not text already in the field.\")"))
        XCTAssertFalse(guide.contains("Keep Roman Letters"))
        XCTAssertFalse(guide.contains("Keep Typed Text"))
        XCTAssertTrue(guide.contains("Hiragana"))
        XCTAssertTrue(guide.contains("Katakana"))
    }

    func testPreeditFillsSpareWidthLeadingWithoutConstrainingOverflowOrShelfHeight() throws {
        let text = try source()
        let start = try XCTUnwrap(text.range(of: "GeometryReader { viewport in"))
        let end = try XCTUnwrap(text.range(of: ".frame(height: 30)", range: start.upperBound..<text.endIndex))
        let preedit = text[start.lowerBound..<end.upperBound]
        XCTAssertTrue(preedit.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(preedit.contains(".frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .leading)"),
                      "Short content must fill the viewport at its leading edge, not float at trailing")
        XCTAssertTrue(preedit.contains(".defaultScrollAnchor(.trailing)"), "Overflow follows the insertion tail")
        XCTAssertFalse(preedit.contains(".frame(width:"), "Do not clamp or squeeze long preedit")
        XCTAssertFalse(preedit.contains("Text(display.rawInput)"), "Do not duplicate the literal spelling next to kana preedit")
        XCTAssertFalse(text.contains("minimumScaleFactor"))
        XCTAssertTrue(text.contains(".frame(height: 30)"))
        XCTAssertTrue(text.contains(".frame(height: compact ? 44 : 74)"))
    }

    // MARK: 1.5.1 — unreadable enabled language and the shared last-chosen mode

    func testUnreadableLanguagePanelReplacesFullAccessFootnotesAndKeepsEscapes() throws {
        let text = try source("Keyboard/KeyboardViewController.swift")
        let panel = try block(in: text, startingAt: "    private var conversionRecoveryPanel: some View {")
        let unreadable = try block(in: panel, startingAt: "                if let unreadable {")
        XCTAssertTrue(unreadable.contains("Label(unreadable.title(language: keyboardModeLabel(language.mode)), systemImage: \"exclamationmark.triangle\")"))
        XCTAssertTrue(unreadable.contains(".font(.headline)"))
        XCTAssertTrue(unreadable.contains("Text(unreadable.body(language: keyboardModeLabel(language.mode)))"))
        XCTAssertTrue(unreadable.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(unreadable.contains("KeyboardLanguageInformativeInk.secondary"))
        XCTAssertFalse(unreadable.contains("Button("), "No Open Uniboard button; the panel never changes settings")
        XCTAssertFalse(unreadable.contains(".accessibilityHidden("), "VoiceOver reads the visible title and body")
        // Today's general Full Access subheadline and footnotes are suppressed in the new state.
        XCTAssertTrue(panel.contains("if language.status == .missingResources,\n                   language.mode.conversionEngineABI != nil, unreadable == nil {"))
        // Order: title, body, Switch to Direct Typing, then unfinished-text controls.
        let title = try XCTUnwrap(panel.range(of: "unreadable.title("))
        let body = try XCTUnwrap(panel.range(of: "unreadable.body("))
        let escape = try XCTUnwrap(panel.range(of: "Button(\"Switch to Direct Typing\") { controller?.switchToDirectTyping() }"))
        let keep = try XCTUnwrap(panel.range(of: "Button(\"Keep Typed Text\")"))
        XCTAssertLessThan(title.lowerBound, body.lowerBound)
        XCTAssertLessThan(body.lowerBound, escape.lowerBound)
        XCTAssertLessThan(escape.lowerBound, keep.lowerBound)
        XCTAssertTrue(panel.contains("ScrollView {"), "Scrollable at large text and in landscape")
        // The existing Download required state is unchanged.
        XCTAssertTrue(text.contains("case .missingResources: return \"Download required. Open Uniboard to manage languages.\""))
        // Two-Set Hangul also gets the panel (instead of its shelf) only in this state.
        XCTAssertTrue(text.contains("} else if needsConversionRecovery && (language.mode != .koreanTwoSetHangul || unreadableNotice != nil) {"))
        XCTAssertTrue(text.contains("((language.mode == .koreanTwoSetHangul && unreadableNotice == nil) || (!isConversionLoading && !needsConversionRecovery))"))
        // Panel state chosen by the keyboard's own Full Access state.
        let state = try block(in: text, startingAt: "    fileprivate func unreadableNotice(for mode: LanguageInputMode)")
        XCTAssertTrue(state.contains("LanguageUnreadableNotice.state(for: mode, unavailable: language.unavailableModes[mode], hasFullAccess: hasFullAccess)"))
        // One announcement of the title per opening, never on later refreshes; focus never moves.
        let announce = try block(in: text, startingAt: "    private func announceUnreadablePanelIfNeeded()")
        XCTAssertTrue(announce.contains("announcesUnreadablePanel = false"))
        XCTAssertTrue(announce.contains("guard unreadablePanelIsOnScreen else { return }"), "Only while the panel is actually visible")
        XCTAssertTrue(announce.contains("UIAccessibility.post(notification: .announcement, argument: title)"))
        XCTAssertFalse(announce.contains(".layoutChanged"))
        XCTAssertFalse(announce.contains(".screenChanged"))
        let appear = try block(in: text, startingAt: "    override func viewWillAppear(_ animated: Bool)")
        XCTAssertLessThan(try XCTUnwrap(appear.range(of: "announcesUnreadablePanel = true")).lowerBound,
                          try XCTUnwrap(appear.range(of: "language.refresh()")).lowerBound)
    }

    func testUnreadableModesStayInSpaceBarChoicesWithQuieterInkAndSpokenReason() throws {
        let text = try source("Keyboard/KeyboardViewController.swift")
        XCTAssertTrue(text.contains("ids += language.enabledModes.filter { $0 != .direct && $0 != .koreanRomaja }"))
        XCTAssertTrue(text.contains("return \"Switch to \\(KeyboardLanguageCoordinator.name(for: mode)), \\(notice.accessibilityValue). \\(notice.compact(language: keyboardModeLabel(mode)))\""))
        XCTAssertTrue(text.contains("return KeyboardLanguageInformativeInk.secondaryUI"))
        let coordinator = try source("Keyboard/KeyboardLanguageCoordinator.swift")
        let refresh = try block(in: coordinator, startingAt: "    func refreshResources() async")
        XCTAssertTrue(refresh.contains("root = rootProvider()"), "The store root is re-resolved on every refresh")
        XCTAssertTrue(refresh.contains("enabledModes = LanguageInputChoicePolicy.choices(enabled: preferences, ready: ready, unavailable: unavailableModes)"))
        XCTAssertFalse(refresh.contains("enabledModes = ready.filter"), "Unreadable enabled languages must not silently vanish")
        let worker = try block(in: coordinator, startingAt: "    func availableModes(")
        for reason in ["case .unreadable: result.unavailable[mode] = .unreadable",
                       "case .absent, .missing: result.unavailable[mode] = .missing",
                       "case .corrupt, .incompatible: result.unavailable[mode] = .damaged",
                       "} else { result.unavailable[mode] = .mismatched }"] {
            XCTAssertTrue(worker.contains(reason), reason)
        }
        let activate = try block(in: coordinator, startingAt: "    func activate(mode:")
        XCTAssertTrue(activate.contains("case .unreadable:\n            return .init(lease: nil, scratch: nil, status: .missingResources, unreadable: true)"))
    }

    func testSwitchToDirectTypingAndSpaceBarChoicesWriteTheRememberedMode() throws {
        let text = try source("Keyboard/KeyboardViewController.swift")
        let transition = try block(in: text, startingAt: "    private func performInputModeTransition(")
        XCTAssertTrue(transition.contains("if language.select(.direct) { rememberChosenMode(.direct, previous: previous) }"),
                      "Switch to Direct Typing in the panel stores Direct as the remembered language")
        let target = try block(in: text, startingAt: "    private func switchInputTarget(")
        XCTAssertTrue(target.contains("guard language.select(mode) else { return }\n            rememberChosenMode(mode, previous: previous)"))
        XCTAssertTrue(target.contains("if language.select(.direct) { rememberChosenMode(.direct, previous: previous) }"))
        let remember = try block(in: text, startingAt: "    private func rememberChosenMode(")
        XCTAssertTrue(remember.contains("LanguageInputChoicePolicy.choiceShouldBeStored(mode, previous: previous)"))
        XCTAssertTrue(remember.contains("rememberedModeQueue.async {"), "No file write or fsync on the main thread")
        XCTAssertTrue(remember.contains("storedBefore == mode || (canWrite && store.save(mode))"), "An unchanged value isn't rewritten")
        XCTAssertTrue(remember.contains("LanguageInputChoicePolicy.lastSeenAfterChoice("))
        let refreshed = try block(in: text, startingAt: "    private func languageDidRefresh()")
        XCTAssertTrue(refreshed.contains("LanguageInputChoicePolicy.rememberedDecision("))
        XCTAssertTrue(refreshed.contains("hasComposition: language.hasComposition"))
        XCTAssertTrue(refreshed.contains("language.isConverting"))
        XCTAssertTrue(refreshed.contains("hasTypedSinceAppear: typedSinceAppear, hasFullAccess: hasFullAccess"))
        XCTAssertTrue(refreshed.contains("pendingRememberedWrites > 0"))
        XCTAssertFalse(refreshed.contains(".save("), "Restoring never writes the stored value back")
        let restore = try block(in: text, startingAt: "    private func restoreRememberedMode(")
        XCTAssertTrue(restore.contains("guard language.select(mode) else { return false }"))

        let app = try source("App/LanguageManagementModel.swift")
        let select = try block(in: app, startingAt: "    func select(_ mode: LanguageInputMode) {")
        XCTAssertTrue(select.contains("remember(mode)"))
        let remembered = try block(in: app, startingAt: "    private func remember(_ mode: LanguageInputMode) {")
        XCTAssertTrue(remembered.contains("lastMode.save(mode)"))
        XCTAssertTrue(remembered.contains("onChange?()"), "Posts the existing payload-free Darwin notification")
        XCTAssertFalse(app.contains("if !canSelect(selectedMode) { selectedMode = .direct }"),
                       "Every reset also stores Direct Typing")
    }
}
#endif
