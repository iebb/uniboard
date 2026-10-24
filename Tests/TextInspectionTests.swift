import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class TextInspectionTests: XCTestCase {
    /// A small catalog: enough metadata to check every row rule.
    private func lookup(_ value: UInt32) -> UnicodeCharacter? {
        switch value {
        case 0x0065: return UnicodeCharacter(codePoint: value, name: "LATIN SMALL LETTER E", detail: "", blockName: "Basic Latin", category: "Ll", script: "Latin")
        case 0x0041: return UnicodeCharacter(codePoint: value, name: "LATIN CAPITAL LETTER A", detail: "", blockName: "Basic Latin", category: "Lu", script: "Latin")
        case 0x0061: return UnicodeCharacter(codePoint: value, name: "LATIN SMALL LETTER A", detail: "", blockName: "Basic Latin", category: "Ll", script: "Latin")
        case 0x0301: return UnicodeCharacter(codePoint: value, name: "COMBINING ACUTE ACCENT", detail: "", blockName: "Combining Diacritical Marks", category: "Mn", script: "Inherited")
        case 0x0340: return UnicodeCharacter(codePoint: value, name: "COMBINING GRAVE TONE MARK", detail: "", blockName: "Combining Diacritical Marks", category: "Mn", script: "Inherited")
        case 0x03B1: return UnicodeCharacter(codePoint: value, name: "GREEK SMALL LETTER ALPHA", detail: "", blockName: "Greek and Coptic", category: "Ll", script: "Greek")
        case 0x0020: return UnicodeCharacter(codePoint: value, name: "SPACE", detail: "", blockName: "Basic Latin", category: "Zs", script: "Common")
        case 0x000D: return UnicodeCharacter(codePoint: value, name: "CARRIAGE RETURN", detail: "", blockName: "Basic Latin", category: "Cc", script: "Common")
        case 0x000A: return UnicodeCharacter(codePoint: value, name: "LINE FEED", detail: "", blockName: "Basic Latin", category: "Cc", script: "Common")
        case 0x200D: return UnicodeCharacter(codePoint: value, name: "ZERO WIDTH JOINER", detail: "", blockName: "General Punctuation", category: "Cf", isInvisible: true, script: "Inherited")
        case 0x1F469: return UnicodeCharacter(codePoint: value, name: "WOMAN", detail: "", blockName: "Miscellaneous Symbols and Pictographs", category: "So", script: "Common")
        case 0x1F4BB: return UnicodeCharacter(codePoint: value, name: "PERSONAL COMPUTER", detail: "", blockName: "Miscellaneous Symbols and Pictographs", category: "So", script: "Common")
        case 0x05C8: return UnicodeCharacter(codePoint: value, name: "UNASSIGNED", detail: "", blockName: "Hebrew", category: "Cn", isInvisible: true, script: "Unknown")
        case 0x0378: return UnicodeCharacter(codePoint: value, name: "UNASSIGNED", detail: "", blockName: "No Block", category: "Cn", isInvisible: true)
        case 0xFDD0: return UnicodeCharacter(codePoint: value, name: "NONCHARACTER", detail: "", blockName: "Arabic Presentation Forms-A", category: "Cn", isInvisible: true)
        case 0x0E80: return UnicodeCharacter(codePoint: value, name: "", detail: "", blockName: "", category: "")
        case 0x3FFFD: return UnicodeCharacter(codePoint: value, name: "NEW IDEOGRAPH", detail: "", blockName: "No Block", category: "Lo")
        default: return nil
        }
    }

    private func analyze(_ text: String, after: String = "", version: String? = "17.0.0",
                         systemAssigns: (Unicode.Scalar) -> Bool = { _ in true }) -> TextInspection {
        TextInspection.analyze(before: text, after: after, catalogVersion: version, lookup: lookup, systemAssigns: systemAssigns)
    }

    func testMixedTextCountsClustersAndNormalizationInOriginalOrder() {
        let inspection = analyze("e\u{301}\u{1F469}\u{200D}", after: "\u{1F4BB} A\u{3B1}")
        XCTAssertEqual(inspection.text, "e\u{301}\u{1F469}\u{200D}\u{1F4BB} A\u{3B1}")
        XCTAssertEqual(inspection.codePointCount, 8)
        XCTAssertEqual(inspection.clusterCount, 5)
        XCTAssertEqual(inspection.utf16Count, 10)
        XCTAssertEqual(inspection.totals, "8 code points · 5 grapheme clusters · 10 UTF-16 code units")
        XCTAssertEqual(inspection.clusters.map(\.text), ["e\u{301}", "\u{1F469}\u{200D}\u{1F4BB}", " ", "A", "\u{3B1}"])
        XCTAssertEqual(inspection.clusters.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertEqual(inspection.clusters.flatMap { $0.scalars.map(\.id) }, Array(0..<8))
        XCTAssertEqual(inspection.clusters[1].scalars.map(\.label), ["U+1F469", "U+200D", "U+1F4BB"])
        XCTAssertEqual(inspection.clusters[1].accessibilityLabel, "Grapheme cluster 2, 3 code points")
        XCTAssertEqual(inspection.clusters[3].accessibilityLabel, "Grapheme cluster 4, 1 code point")
        XCTAssertEqual(inspection.normalization.map(\.status), [.differs, .already, .differs, .already])
        XCTAssertEqual(inspection.normalization.map(\.id), ["NFC", "NFD", "NFKC", "NFKD"])
        XCTAssertEqual(inspection.normalization[0].accessibilityLabel, "NFC, differs from this form")
        XCTAssertEqual(inspection.normalization[1].accessibilityLabel, "NFD, already in this form")
        XCTAssertEqual(inspection.codePointSequence, "U+0065 U+0301 U+1F469 U+200D U+1F4BB U+0020 U+0041 U+03B1")
        XCTAssertNil(inspection.versionNote)
        // The emoji and accented letter draw naturally; the space shows its marker.
        XCTAssertEqual(inspection.clusters.map(\.tileText), ["e\u{301}", "\u{1F469}\u{200D}\u{1F4BB}", "␣", "A", "\u{3B1}"])
        XCTAssertEqual(inspection.clusters.map(\.usesMarker), [false, false, true, false, false])
        XCTAssertTrue(inspection.usesMarkers)
        XCTAssertEqual(inspection.footnotes, [TextInspectionWording.scopeNote, TextInspectionWording.markerNote, TextInspectionWording.snapshotNote])
    }

    func testRowsShowNameCategoryBlockAndExpandedProperties() throws {
        let row = try XCTUnwrap(analyze("\u{3B1}").clusters.first?.scalars.first)
        XCTAssertEqual(row.label, "U+03B1")
        XCTAssertEqual(row.name, "GREEK SMALL LETTER ALPHA")
        XCTAssertFalse(row.nameIsNote)
        XCTAssertEqual(row.detail, "Lowercase letter (Ll) · Greek and Coptic")
        XCTAssertEqual(row.accessibilityLabel, "U+03B1, GREEK SMALL LETTER ALPHA")
        XCTAssertEqual(row.accessibilityCategoryBlock, "Lowercase letter, Greek and Coptic")
        XCTAssertEqual(row.properties, [
            TextInspectionProperty(title: "Code point", value: "U+03B1", identifier: "codePoint", monospaced: true),
            TextInspectionProperty(title: "Name", value: "GREEK SMALL LETTER ALPHA", identifier: "name"),
            TextInspectionProperty(title: "Category", value: "Lowercase letter (Ll)", identifier: "category"),
            TextInspectionProperty(title: "Unicode block", value: "Greek and Coptic", identifier: "block"),
            TextInspectionProperty(title: "Script", value: "Greek", identifier: "script")])
        let single = analyze("a")
        XCTAssertEqual(single.totals, "1 code point · 1 grapheme cluster · 1 UTF-16 code unit")
        XCTAssertEqual(single.normalization.map(\.status), [.already, .already, .already, .already])
        XCTAssertFalse(single.usesMarkers)
        XCTAssertEqual(single.footnotes, [TextInspectionWording.scopeNote, TextInspectionWording.snapshotNote])
    }

    func testUnassignedAndMissingMetadataAreDisclosedNotGuessed() throws {
        let unassigned = try XCTUnwrap(analyze("\u{5C8}").clusters.first)
        XCTAssertEqual(unassigned.scalars[0].name, "Unassigned in Unicode 17.0")
        XCTAssertTrue(unassigned.scalars[0].nameIsNote)
        XCTAssertEqual(unassigned.scalars[0].detail, "Hebrew")
        XCTAssertEqual(unassigned.scalars[0].properties.map(\.value),
                       ["U+05C8", "Unassigned in Unicode 17.0", "Unassigned code point (Cn)", "Hebrew", "Unknown"])
        // The catalog's own placeholder for an unassigned (invisible) code point.
        XCTAssertEqual(unassigned.tileText, "◌")
        XCTAssertTrue(unassigned.usesMarker)

        let noBlock = try XCTUnwrap(analyze("\u{378}", version: "19.0.0 draft").clusters.first?.scalars.first)
        XCTAssertEqual(noBlock.name, "Unassigned in Unicode 19.0 draft")
        XCTAssertEqual(noBlock.detail, "")
        XCTAssertEqual(noBlock.properties.map(\.value), ["U+0378", "Unassigned in Unicode 19.0 draft", "Unassigned code point (Cn)", "No Unicode block"])

        // Without catalog data nothing is called unassigned.
        let unknownVersion = try XCTUnwrap(analyze("\u{5C8}", version: nil).clusters.first?.scalars.first)
        XCTAssertEqual(unknownVersion.name, "UNASSIGNED")
        XCTAssertFalse(unknownVersion.nameIsNote)
        XCTAssertEqual(unknownVersion.detail, "Unassigned code point (Cn) · Hebrew")

        let noncharacter = try XCTUnwrap(analyze(String(Unicode.Scalar(0xFDD0)!)).clusters.first?.scalars.first)
        XCTAssertEqual(noncharacter.name, "NONCHARACTER")

        let missing = try XCTUnwrap(analyze("\u{E01}").clusters.first?.scalars.first)
        XCTAssertEqual(missing.name, "Not available")
        XCTAssertTrue(missing.nameIsNote)
        XCTAssertEqual(missing.detail, "Not available")
        XCTAssertEqual(missing.properties.map(\.value), ["U+0E01", "Not available", "Not available", "Not available"])
        XCTAssertEqual(missing.accessibilityCategoryBlock, "Not available, Not available")

        let empty = try XCTUnwrap(analyze("\u{E80}").clusters.first?.scalars.first)
        XCTAssertEqual(empty.name, "Not available")
        XCTAssertEqual(empty.detail, "Not available · Not available")
        XCTAssertEqual(empty.properties.count, 4, "No script row without script metadata")
        XCTAssertEqual(empty.accessibilityCategoryBlock, "Not available, Not available")
        XCTAssertFalse(analyze("\u{E01}").clusters[0].usesMarker, "Unknown scalars draw naturally")
    }

    func testMarkersForMarksControlsAndInvisibleCharactersOnlyInTiles() {
        let inspection = analyze("\u{301}a\r\n\u{200D}")
        XCTAssertEqual(inspection.clusters.map(\.text), ["\u{301}", "a", "\r\n", "\u{200D}"])
        XCTAssertEqual(inspection.clusters.map(\.tileText), ["◌\u{301}", "a", "↵", "◌"])
        XCTAssertEqual(inspection.clusters.map(\.usesMarker), [true, false, true, true])
        // Markers never reach the copied data.
        XCTAssertEqual(inspection.text, "\u{301}a\r\n\u{200D}")
        XCTAssertEqual(inspection.codePointSequence, "U+0301 U+0061 U+000D U+000A U+200D")
        XCTAssertEqual(analyze("\u{10FFFD}").codePointSequence, "U+10FFFD")
        // A space whose mark the catalog doesn't know isn't only invisible parts: drawn as is.
        let spaced = analyze(" \u{300}").clusters
        XCTAssertEqual(spaced.map(\.text), [" \u{300}"])
        XCTAssertEqual(spaced.map(\.tileText), [" \u{300}"])
        XCTAssertEqual(spaced.map(\.usesMarker), [false])
    }

    func testSystemOlderThanCatalogMakesNormalizationUnavailableWithANote() {
        let lagging = analyze("a\u{3FFFD}", systemAssigns: { $0.value != 0x3FFFD })
        XCTAssertEqual(lagging.normalization.map(\.status), [.unavailable, .unavailable, .unavailable, .unavailable])
        XCTAssertEqual(lagging.versionNote, "Character details use Unicode 17.0. Grouping and normalization use this version of iOS.")
        XCTAssertEqual(lagging.footnotes.last, lagging.versionNote)
        XCTAssertNil(analyze("a\u{3FFFD}", version: nil, systemAssigns: { $0.value != 0x3FFFD }).versionNote)
        // Unassigned in the catalog too: no difference is established.
        XCTAssertNil(analyze("\u{5C8}", systemAssigns: { _ in false }).versionNote)
        // The default reads the system's own Unicode ages.
        let system = TextInspection.analyze(before: "a", after: "", catalogVersion: "17.0.0", lookup: lookup)
        XCTAssertNil(system.versionNote)
    }

    func testFrozenTextDropsOnlyThePreviewsTruncationMarks() {
        XCTAssertTrue(TextInspection.frozenText(before: "…abc", after: "de…", beforeTruncated: true, afterTruncated: true) == ("abc", "de"))
        XCTAssertTrue(TextInspection.frozenText(before: "…abc", after: "de…", beforeTruncated: false, afterTruncated: false) == ("…abc", "de…"))
        XCTAssertTrue(TextInspection.frozenText(before: "…\u{301}x", after: "", beforeTruncated: true, afterTruncated: false) == ("\u{301}x", ""))
        XCTAssertTrue(TextInspection.frozenText(before: "abc", after: "", beforeTruncated: true, afterTruncated: true) == ("abc", ""))
    }

    func testStatesAndTheirWording() {
        func state(_ before: String, _ after: String = "", context: Bool = true, restricted: Bool = false) -> TextInspectionState {
            TextInspectionState.inspect(before: before, after: after, beforeTruncated: true, afterTruncated: true,
                                        contextAvailable: context, restricted: restricted, catalogVersion: "17.0.0",
                                        lookup: lookup, systemAssigns: { _ in true })
        }
        XCTAssertEqual(state("abc", restricted: true), .restricted)
        XCTAssertEqual(state("", context: false), .unavailable)
        XCTAssertEqual(state("…", "…"), .empty)
        XCTAssertEqual(state(String(repeating: "e\u{301}", count: 513)), .failed)
        let ready = state("…ab", "c…")
        XCTAssertEqual(ready.inspection?.before, "ab")
        XCTAssertEqual(ready.inspection?.after, "c")
        XCTAssertNil(ready.message)
        XCTAssertNil(TextInspectionState.empty.inspection)
        XCTAssertEqual(TextInspectionState.empty.message?.title, "No text to inspect")
        XCTAssertEqual(TextInspectionState.empty.message?.text, "Show some text in the preview, then choose Inspect.")
        XCTAssertEqual(TextInspectionState.empty.message?.symbol, "text.magnifyingglass")
        XCTAssertEqual(TextInspectionState.unavailable.message?.title, "Preview text unavailable")
        XCTAssertEqual(TextInspectionState.unavailable.message?.text, "This app hasn’t made text available to the keyboard.")
        XCTAssertEqual(TextInspectionState.unavailable.message?.symbol, "text.badge.xmark")
        XCTAssertEqual(TextInspectionState.restricted.message?.title, "Inspection unavailable here")
        XCTAssertEqual(TextInspectionState.restricted.message?.symbol, "lock")
        XCTAssertEqual(TextInspectionState.failed.message?.title, "Couldn’t inspect this text")
        XCTAssertEqual(TextInspectionState.failed.message?.text, "Close and try again. Your text hasn’t changed.")
        // The default system lookup.
        let system = TextInspectionState.inspect(before: "a", after: "", beforeTruncated: false, afterTruncated: false,
                                                 contextAvailable: true, restricted: false, catalogVersion: nil, lookup: lookup)
        XCTAssertEqual(system.inspection?.codePointCount, 1)
    }

    func testCopyStateNoticesAndConfirmation() {
        var blocked = TextInspectionCopyState(hasFullAccess: false)
        XCTAssertFalse(blocked.canCopy)
        XCTAssertEqual(blocked.notice, .fullAccessRequired)
        XCTAssertNil(blocked.noticeText?.title)
        XCTAssertEqual(blocked.noticeText?.body, "To copy from the inspector, allow Full Access for Uniboard in your keyboard settings. You can still inspect text and type without it.")
        blocked.record(.copied, for: .text)
        XCTAssertTrue(blocked.canCopy)

        var state = TextInspectionCopyState(hasFullAccess: true)
        XCTAssertTrue(state.canCopy)
        XCTAssertNil(state.noticeText)
        state.record(.copied, for: .codePoints)
        XCTAssertEqual(state.confirmed, .codePoints)
        state.endConfirmation(.text)
        XCTAssertEqual(state.confirmed, .codePoints)
        state.endConfirmation(.codePoints)
        XCTAssertNil(state.confirmed)
        state.record(.failed, for: .text)
        XCTAssertEqual(state.notice, .failed(.text))
        XCTAssertTrue(state.canCopy, "One failure offers Try Again")
        XCTAssertEqual(state.noticeText?.title, "Couldn’t copy text")
        XCTAssertEqual(state.noticeText?.body, "Try again. Your text hasn’t changed.")
        state.record(.failed, for: .codePoints)
        XCTAssertEqual(state.notice, .blocked)
        XCTAssertFalse(state.canCopy)
        XCTAssertEqual(state.noticeText?.body, "iOS isn’t allowing this keyboard to copy. You can still inspect text and type normally.")
        XCTAssertNil(state.noticeText?.title)
        var other = TextInspectionCopyState(hasFullAccess: true)
        other.record(.failed, for: .codePoints)
        XCTAssertEqual(other.noticeText?.title, "Couldn’t copy code points")
        other.record(.copied, for: .text)
        other.record(.failed, for: .text)
        XCTAssertEqual(other.notice, .failed(.text), "A success resets the failure count")
        other.record(.fullAccessRequired, for: .text)
        XCTAssertEqual(other.notice, .fullAccessRequired)
        XCTAssertFalse(other.canCopy)
    }

    func testWordingAndForms() {
        XCTAssertEqual(TextInspectionWording.versionLabel("18.0.0"), "18.0")
        XCTAssertEqual(TextInspectionWording.versionLabel("17.0"), "17.0")
        XCTAssertEqual(TextInspectionWording.versionLabel("16.0.1"), "16.0.1")
        XCTAssertEqual(TextInspectionWording.versionLabel("19.0.0 draft"), "19.0 draft")
        XCTAssertEqual(TextInspectionWording.codePoints(2), "2 code points")
        XCTAssertEqual(TextInspectionWording.copied(.text), "Text copied")
        XCTAssertEqual(TextInspectionWording.copied(.codePoints), "Code points copied")
        XCTAssertEqual(TextNormalizationForm.allCases.map(\.summary), ["Canonical composition", "Canonical decomposition",
                                                                       "Compatibility composition", "Compatibility decomposition"])
        XCTAssertEqual([TextNormalizationStatus.already, .differs, .unavailable].map(\.title),
                       ["Already in this form", "Differs from this form", "Not available"])
        XCTAssertEqual([TextNormalizationStatus.already, .differs, .unavailable].map(\.symbol), ["equal", "notequal", "minus"])
        XCTAssertEqual(TextNormalizationForm.nfkc.normalize("x\u{B2}"), "x2")
        XCTAssertEqual(TextNormalizationForm.nfkd.normalize("\u{E9}").unicodeScalars.count, 2)
    }

    // MARK: Copy each form and encoding (design/inspect/copy-forms/design.md)

    /// "Café 👩🏽‍💻 x²" typed with e + U+0301 (§5 checks 1–3).
    private let cafe = "Cafe\u{301} \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB} x\u{B2}"

    func testFormsListOnlyTheirChangesPerCluster() throws {
        let inspection = analyze(cafe)
        XCTAssertEqual(inspection.normalization.map(\.status), [.differs, .already, .differs, .differs])
        let lines = inspection.normalization.map { $0.changes.map(\.line) }
        XCTAssertEqual(lines, [["e\u{301}  U+0065 U+0301 → U+00E9"], [],
                               ["e\u{301}  U+0065 U+0301 → U+00E9", "\u{B2}  U+00B2 → U+0032"],
                               ["\u{B2}  U+00B2 → U+0032"]])
        let nfc = inspection.normalization[0]
        XCTAssertEqual(nfc.changes[0].display, "e\u{301}")
        XCTAssertEqual(nfc.changes[0].codePoints, "U+0065 U+0301 → U+00E9")
        XCTAssertEqual(nfc.changes[0].before, [0x65, 0x301])
        XCTAssertEqual(nfc.changes[0].after, [0xE9])
        XCTAssertEqual(nfc.changes[0].id, [0x65, 0x301])
        XCTAssertNil(nfc.changes[0].occurrences)
        XCTAssertNil(nfc.moreChanges)
        XCTAssertEqual(nfc.hiddenChangeCount, 0)
        XCTAssertEqual(nfc.accessibilityRowLabel, "NFC, canonical composition")
        XCTAssertEqual(nfc.accessibilityRowValue, "differs from this form, e\u{301}  U+0065 U+0301 → U+00E9")
        XCTAssertEqual(inspection.normalization[1].accessibilityRowValue, "already in this form")
        XCTAssertTrue(inspection.normalization.allSatisfy(\.canCopy))

        // Copies give each form; the inspected text never changes.
        XCTAssertEqual(inspection.copyValue(for: .form(.nfc)).map { Array($0.unicodeScalars) },
                       Array("Caf\u{E9} \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB} x\u{B2}".unicodeScalars))
        XCTAssertEqual(inspection.copyValue(for: .form(.nfkd)).map { Array($0.unicodeScalars) },
                       Array("Cafe\u{301} \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB} x2".unicodeScalars))
        XCTAssertEqual(inspection.copyValue(for: .form(.nfd)).map { Array($0.unicodeScalars) }, Array(cafe.unicodeScalars))
        XCTAssertEqual(inspection.copyValue(for: .text).map { Array($0.unicodeScalars) }, Array(cafe.unicodeScalars))
        XCTAssertEqual(inspection.copyValue(for: .codePoints), inspection.codePointSequence)
        XCTAssertEqual(Array(inspection.text.unicodeScalars), Array(cafe.unicodeScalars))

        // A mark alone draws with the tiles' dotted circle.
        let mark = try XCTUnwrap(analyze("\u{340}").normalization.first?.changes.first)
        XCTAssertEqual(mark.line, "◌\u{340}  U+0340 → U+0300")
    }

    func testRepeatedChangesShowOnceAndAtMostFourLines() throws {
        let repeated = analyze(String(repeating: "e\u{301} ", count: 5)).normalization[0]
        XCTAssertEqual(repeated.changes.count, 1)
        XCTAssertEqual(repeated.changes[0].count, 5)
        XCTAssertEqual(repeated.changes[0].occurrences, "×5")
        XCTAssertEqual(repeated.changes[0].line, "e\u{301}  U+0065 U+0301 → U+00E9 ×5")
        XCTAssertEqual(repeated.accessibilityRowValue, "differs from this form, e\u{301}  U+0065 U+0301 → U+00E9, 5 occurrences")

        // Seven distinct changes, in order of first appearance.
        let seven = analyze("a\u{301}e\u{301}i\u{301}e\u{301}o\u{301}u\u{301}c\u{301}n\u{301}").normalization[0]
        XCTAssertEqual(seven.changes.map(\.after), [[0xE1], [0xE9], [0xED], [0xF3], [0xFA], [0x107], [0x144]])
        XCTAssertEqual(seven.changes.map(\.count), [1, 2, 1, 1, 1, 1, 1])
        XCTAssertEqual(seven.shownChanges.map(\.after), [[0xE1], [0xE9], [0xED], [0xF3]])
        XCTAssertEqual(seven.hiddenChangeCount, 3)
        XCTAssertEqual(seven.moreChanges, "+3 more")
        XCTAssertTrue(seven.accessibilityRowValue.hasSuffix("U+0065 U+0301 → U+00E9, 2 occurrences, i\u{301}  U+0069 U+0301 → U+00ED, o\u{301}  U+006F U+0301 → U+00F3, 3 more changes"))
        let five = analyze("a\u{301}e\u{301}i\u{301}o\u{301}u\u{301}").normalization[0]
        XCTAssertEqual(five.moreChanges, "+1 more")
        XCTAssertTrue(five.accessibilityRowValue.hasSuffix(", 1 more change"))
    }

    func testChangesAreHiddenWhenClustersDontAddUpToTheWholeResult() {
        let clusters = analyze("ab").clusters
        // A normalizer that joins across the cluster boundary.
        XCTAssertEqual(TextNormalizationResult.changes(in: clusters, whole: "c", normalize: { $0 == "ab" ? "c" : $0.uppercased() }), [])
        XCTAssertEqual(TextNormalizationResult.changes(in: clusters, whole: "AB", normalize: { $0.uppercased() }).map(\.line),
                       ["a  U+0061 → U+0041", "b  U+0062 → U+0042"])
        // No change lines unless the status is Differs.
        let lagging = analyze("e\u{301}\u{3FFFD}", systemAssigns: { $0.value != 0x3FFFD })
        XCTAssertTrue(lagging.normalization.allSatisfy { $0.changes.isEmpty && !$0.canCopy })
        XCTAssertNil(lagging.copyValue(for: .form(.nfc)))
        XCTAssertNotNil(lagging.copyValue(for: .text))
    }

    func testEncodingsAsLabeledHex() {
        let inspection = analyze(cafe)
        XCTAssertEqual(inspection.encodings.map(\.id), ["UTF-8", "UTF-16"])
        let utf8 = inspection.encodings[0], utf16 = inspection.encodings[1]
        XCTAssertEqual(utf8.hex, "43 61 66 65 CC 81 20 F0 9F 91 A9 F0 9F 8F BD E2 80 8D F0 9F 92 BB 20 78 C2 B2")
        XCTAssertEqual(utf8.count, 26)
        XCTAssertEqual(utf8.countLabel, "26 bytes · hex")
        XCTAssertEqual(utf8.accessibilityLabel, "UTF-8, 26 bytes, hex")
        XCTAssertEqual(utf8.target, .encoding(.utf8))
        XCTAssertEqual(utf16.hex, "0043 0061 0066 0065 0301 0020 D83D DC69 D83C DFFD 200D D83D DCBB 0020 0078 00B2")
        XCTAssertEqual(utf16.count, 16)
        XCTAssertEqual(utf16.count, inspection.utf16Count)
        XCTAssertEqual(utf16.countLabel, "16 code units · hex")
        XCTAssertEqual(utf16.accessibilityLabel, "UTF-16, 16 code units, hex")
        XCTAssertEqual(inspection.copyValue(for: .encoding(.utf8)), utf8.hex)
        XCTAssertEqual(inspection.copyValue(for: .encoding(.utf16)), utf16.hex)

        let long = analyze("“So far so good,” she said \u{1F604} and left")
        XCTAssertEqual(long.encodings.map(\.count), [44, 38])
        XCTAssertTrue(long.encodings[0].hex.hasPrefix("E2 80 9C 53 6F"))
        XCTAssertTrue(long.encodings[1].hex.contains("D83D DE04"))
        XCTAssertFalse(long.encodings[1].hex.contains("\n"))

        let single = analyze("a")
        XCTAssertEqual(single.encodings.map(\.countLabel), ["1 byte · hex", "1 code unit · hex"])
        XCTAssertEqual(single.encodings.map(\.hex), ["61", "0061"])
    }

    func testCollapsedHexShowsOnlyWholeValues() {
        // The long sample's 32-unit preview excerpt, as on device.
        let excerpt = analyze(" far so good,” she said \u{1F604} and l")
        let utf8 = excerpt.encodings[0], utf16 = excerpt.encodings[1]
        XCTAssertEqual(utf16.count, 32)
        XCTAssertEqual(utf16.valueWidth, 4)
        XCTAssertEqual(utf8.valueWidth, 2)

        // 34 columns: 7 units a line, 6 on the last before " …".
        let narrow = utf16.collapsed(columns: 34, maxLines: 3)
        XCTAssertTrue(narrow.truncated)
        XCTAssertTrue(narrow.hex.hasSuffix("0020 0073 0068 0065 0020 0073 …"))
        XCTAssertEqual(narrow.hex.split(separator: " ").count, 7 + 7 + 6 + 1)
        // 38 columns: 7 a line still, and 7 whole units plus " …" fit the last.
        let wide = utf16.collapsed(columns: 38, maxLines: 3)
        XCTAssertTrue(wide.hex.hasSuffix("0020 0073 0068 0065 0020 0073 0061 …"))
        // Every shown value is whole: a prefix of the full value at a value boundary.
        for columns in 1...60 {
            for encoding in [utf8, utf16] {
                let collapsed = encoding.collapsed(columns: columns, maxLines: 3)
                guard collapsed.truncated else { XCTAssertEqual(collapsed.hex, encoding.hex); continue }
                let shown = String(collapsed.hex.dropLast(2))
                XCTAssertTrue(collapsed.hex.hasSuffix(" …"))
                XCTAssertTrue(encoding.hex.hasPrefix(shown + " "), "\(encoding.form) at \(columns)")
                XCTAssertTrue(shown.split(separator: " ").allSatisfy { $0.count == encoding.valueWidth })
            }
        }
        // 36 bytes fit three lines of 13 (38 columns) whole, with no Show All.
        XCTAssertEqual(utf8.count, 36)
        XCTAssertEqual(utf8.collapsed(columns: 38, maxLines: 3).hex, utf8.hex)
        XCTAssertFalse(utf8.collapsed(columns: 38, maxLines: 3).truncated)
        XCTAssertFalse(utf8.collapsed(columns: 35, maxLines: 3).truncated)
        XCTAssertTrue(utf8.collapsed(columns: 34, maxLines: 3).hex.hasSuffix(" …"))
        // A wider ellipsis takes more of the last line.
        XCTAssertTrue(utf16.collapsed(columns: 38, maxLines: 3, trailerColumns: 5).hex.hasSuffix("0020 0073 0068 0065 0020 0073 …"))
        // Only an ellipsis when not even one value fits beside it.
        let lone = utf16.collapsed(columns: 4, maxLines: 1)
        XCTAssertEqual(lone.hex, "…")
        XCTAssertTrue(lone.truncated)
    }

    func testHexValueFitCountsWholeValuesPerLine() {
        let all = HexValueFit(count: 21, valueWidth: 4, columns: 34, maxLines: 3)
        XCTAssertEqual(all.shown, 21)
        XCTAssertFalse(all.truncated)
        let cut = HexValueFit(count: 22, valueWidth: 4, columns: 34, maxLines: 3)
        XCTAssertEqual(cut.shown, 20)
        XCTAssertTrue(cut.truncated)
        // Bytes: 3 columns each, 11 in 34 columns, and still 11 beside " …".
        XCTAssertEqual(HexValueFit(count: 40, valueWidth: 2, columns: 34, maxLines: 3).shown, 33)
        XCTAssertEqual(HexValueFit(count: 40, valueWidth: 2, columns: 33, maxLines: 3),
                       HexValueFit(count: 40, valueWidth: 2, columns: 32, maxLines: 3))
        // Narrower than one value: still one a line; nothing beside the ellipsis.
        let tiny = HexValueFit(count: 5, valueWidth: 4, columns: 2, maxLines: 3)
        XCTAssertEqual(tiny.shown, 2)
        XCTAssertTrue(tiny.truncated)
        // At least one line.
        XCTAssertEqual(HexValueFit(count: 1, valueWidth: 2, columns: 10, maxLines: 0).shown, 1)
        XCTAssertEqual(HexValueFit(count: 0, valueWidth: 2, columns: 10, maxLines: 3).shown, 0)
    }

    func testCopyWordingForEveryTarget() {
        let targets: [TextInspectionCopyTarget] = [.text, .codePoints, .form(.nfc), .form(.nfkd), .encoding(.utf8), .encoding(.utf16)]
        XCTAssertEqual(targets.map(TextInspectionWording.copied),
                       ["Text copied", "Code points copied", "NFC text copied", "NFKD text copied", "UTF-8 hex copied", "UTF-16 hex copied"])
        XCTAssertEqual(targets.map(TextInspectionWording.copyFailed),
                       ["Couldn’t copy text", "Couldn’t copy code points", "Couldn’t copy NFC text", "Couldn’t copy NFKD text",
                        "Couldn’t copy UTF-8 hex", "Couldn’t copy UTF-16 hex"])
        XCTAssertEqual(targets.map(TextInspectionWording.copyLabel),
                       ["Copy Text", "Copy Code Points", "Copy NFC text", "Copy NFKD text", "Copy UTF-8 hex", "Copy UTF-16 hex"])
        XCTAssertEqual(TextInspectionWording.encodingsSection, "Encodings")
        XCTAssertEqual(TextInspectionWording.showAll, "Show All")
        XCTAssertEqual(TextInspectionWording.showLess, "Show Less")
        XCTAssertEqual(TextInspectionWording.copyHexHint, "Copies the full hexadecimal value")
        XCTAssertEqual(TextInspectionWording.showAll(.utf8), "Show all UTF-8 bytes")
        XCTAssertEqual(TextInspectionWording.showFewer(.utf8), "Show fewer UTF-8 bytes")
        XCTAssertEqual(TextInspectionWording.showAll(.utf16), "Show all UTF-16 code units")
        XCTAssertEqual(TextInspectionWording.showFewer(.utf16), "Show fewer UTF-16 code units")
        XCTAssertEqual(TextInspectionWording.bytes(2), "2 bytes · hex")
        XCTAssertEqual(TextInspectionWording.codeUnits(2), "2 code units · hex")
        XCTAssertEqual(TextInspectionWording.occurrences(3), "×3")
        XCTAssertEqual(TextInspectionWording.occurrencesSpoken(3), "3 occurrences")
        XCTAssertEqual(TextInspectionWording.moreChanges(2), "+2 more")
        XCTAssertEqual(TextInspectionWording.moreChangesSpoken(2), "2 more changes")

        // One confirmation at a time across every copy in the panel.
        var state = TextInspectionCopyState(hasFullAccess: true)
        state.record(.copied, for: .form(.nfc))
        XCTAssertEqual(state.confirmed, .form(.nfc))
        state.record(.copied, for: .encoding(.utf16))
        XCTAssertEqual(state.confirmed, .encoding(.utf16))
        state.endConfirmation(.form(.nfc))
        XCTAssertEqual(state.confirmed, .encoding(.utf16))
        state.record(.failed, for: .form(.nfd))
        XCTAssertNil(state.confirmed)
        XCTAssertEqual(state.noticeText?.title, "Couldn’t copy NFD text")
        XCTAssertEqual(state.noticeText?.body, "Try again. Your text hasn’t changed.")
        state.record(.failed, for: .encoding(.utf8))
        XCTAssertFalse(state.canCopy)
    }

    func testBundledCatalogNamesHebrewAndAnUnassignedCodePoint() throws {
        let catalog = UnicodeCatalog.shared
        let inspection = TextInspection.analyze(before: "\u{5D1}\u{5BC}\u{378}", after: "", catalogVersion: catalog.version,
                                                lookup: catalog.character(at:))
        XCTAssertEqual(inspection.clusterCount, 2)
        XCTAssertEqual(inspection.clusters[0].scalars.map(\.name), ["HEBREW LETTER BET", "HEBREW POINT DAGESH OR MAPIQ"])
        XCTAssertEqual(inspection.clusters[0].scalars[0].detail, "Letter (Lo) · Hebrew")
        XCTAssertEqual(inspection.clusters[1].scalars[0].name, "Unassigned in Unicode " + TextInspectionWording.versionLabel(catalog.version))
        XCTAssertEqual(inspection.clusters[1].scalars[0].detail, "Greek and Coptic")
        XCTAssertEqual(inspection.clusters[1].tileText, "◌")
    }
}
