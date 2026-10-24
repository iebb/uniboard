import SwiftUI
import UIKit
import CoreText

/// The saved font rules as the app's screens see them. Every change is saved
/// through `FontRuleStore`, which validates and never repairs; a refused save
/// changes nothing. Saving never touches the Extra Unicode Fonts switch: off
/// pauses rules, and the screens say so. The keyboard reads the same file on
/// its next appear.
@MainActor
final class FontRulePreferences: ObservableObject {
    static let shared = FontRulePreferences()

    /// Whether a rule's face can be used, as far as the face itself decides.
    enum Status: Equatable {
        case applied
        /// "Font unavailable"
        case unavailable
        /// "Font can’t display this text": only for a code point rule whose
        /// face has no glyph for it. A range or block face that draws only
        /// some characters is not an error.
        case cannotDisplay

        var text: String? {
            switch self {
            case .applied: return nil
            case .unavailable: return FontRuleCopy.unavailable
            case .cannotDisplay: return FontRuleCopy.cannotDisplay
            }
        }
    }

    @Published private(set) var rules: [FontRule]
    private let store: FontRuleStore
    private let catalog: CatalogPreferences
    private var loaded: [String: Result<LoadedRuleFont, FontRuleFaceLoader.Unavailable>] = [:]
    private var fonts: [String: UIFont] = [:]
    private var revision = ""

    init(store: FontRuleStore = .shared, catalog: CatalogPreferences = .shared) {
        self.store = store
        self.catalog = catalog
        rules = store.load(blocks: UnicodeCatalog.shared.blocks) ?? []
    }

    /// Reads the saved rules again, for example after the configuration changed.
    func reload() {
        let saved = store.load(blocks: UnicodeCatalog.shared.blocks) ?? []
        if saved != rules { rules = saved }
        catalog.reloadFontRules()
    }

    /// Saves `next` as the complete rule list. False when the store refuses it.
    @discardableResult func save(_ next: [FontRule]) -> Bool {
        guard store.save(next, blocks: UnicodeCatalog.shared.blocks) else { return false }
        rules = next
        catalog.reloadFontRules()
        return true
    }

    func rule(id: String) -> FontRule? { rules.first { $0.id == id } }

    @discardableResult func remove(id: String) -> Bool {
        save(rules.filter { $0.id != id })
    }

    @discardableResult func move(kind: FontRuleKind, from source: IndexSet, to destination: Int) -> Bool {
        guard let next = FontRuleOrdering.moving(rules, kind: kind, from: source, to: destination), next != rules else { return false }
        return save(next)
    }

    func codePointRule(_ codePoint: UInt32) -> FontRule? { FontRuleOrdering.codePointRule(codePoint, in: rules) }

    @discardableResult func setFace(_ face: FontFaceReference, forCodePoint codePoint: UInt32) -> Bool {
        save(FontRuleOrdering.settingFace(face, forCodePoint: codePoint, in: rules))
    }

    @discardableResult func clear(codePoint: UInt32) -> Bool {
        save(FontRuleOrdering.clearing(codePoint: codePoint, in: rules))
    }

    // MARK: Faces

    /// Forgets loaded faces when the font library or downloads changed.
    private func checkRevision() {
        let current = UnicodeFontSupport.ruleFaceLoader.revision
        guard current != revision else { return }
        revision = current
        loaded.removeAll()
        fonts.removeAll()
    }

    private func load(_ face: FontFaceReference) -> LoadedRuleFont? {
        checkRevision()
        let key = face.identityKey + "|" + face.postScriptName
        if let result = loaded[key] { return try? result.get() }
        let result = UnicodeFontSupport.ruleFaceLoader.load(face)
        loaded[key] = result
        return try? result.get()
    }

    /// The face at `size` for tiles and samples, or nil when it can't be loaded.
    func font(_ face: FontFaceReference, size: CGFloat) -> UIFont? {
        checkRevision()
        let key = face.identityKey + "|" + face.postScriptName + "@\(size)"
        if let font = fonts[key] { return font }
        guard let font = load(face)?.font(size: size) else { return nil }
        fonts[key] = font
        return font
    }

    func isAvailable(_ face: FontFaceReference) -> Bool { load(face) != nil }

    /// Whether the face itself has a glyph for every UTF-16 unit of `text`.
    func draws(_ text: String, in face: FontFaceReference) -> Bool {
        guard let loaded = load(face) else { return false }
        var characters = Array(text.utf16)
        guard !characters.isEmpty else { return false }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(loaded.reference, &characters, &glyphs, characters.count)
    }

    func status(of rule: FontRule) -> Status {
        guard isAvailable(rule.face) else { return .unavailable }
        if case let .codePoint(value) = rule.selector, let scalar = Unicode.Scalar(value), !draws(String(scalar), in: rule.face) {
            return .cannotDisplay
        }
        return .applied
    }

    /// What applies to `codePoint` once its own rule is cleared: "Using {font}
    /// · {rule}" for the next rule whose face can draw it, else default fonts.
    func captionAfterClearing(_ codePoint: UInt32) -> String {
        let remaining = FontRuleSet(rules: FontRuleOrdering.clearing(codePoint: codePoint, in: rules))
        guard let scalar = Unicode.Scalar(codePoint) else { return FontRuleCopy.usingDefaultFonts }
        for match in remaining.candidates(for: codePoint) {
            let rule = remaining.rules[match.ruleIndex]
            if draws(String(scalar), in: rule.face) {
                return FontRuleCopy.using(rule.face.displayName) + " · " + FontRuleCopy.source(rule.selector)
            }
        }
        return FontRuleCopy.usingDefaultFonts
    }

    /// The first assigned character of a range or block in the selected
    /// edition, for tiles; a code point's own character.
    static func firstCharacter(of selector: FontRuleSelector, in catalog: UnicodeCatalog) -> UnicodeCharacter? {
        sampleCharacters(of: selector, in: catalog, limit: 1).first
    }

    static func sampleCharacters(of selector: FontRuleSelector, in catalog: UnicodeCatalog, limit: Int) -> [UnicodeCharacter] {
        let (first, last) = selector.bounds
        if case .codePoint = selector { return catalog.character(at: first).map { [$0] } ?? [] }
        return catalog.characters(in: UnicodeBlock(name: "", start: first, end: last), limit: limit)
    }
}
