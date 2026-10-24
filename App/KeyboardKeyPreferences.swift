import SwiftUI

/// Only explicitly edited settings cross into the shared container. Never
/// derives a candidate from a document, search, recent item or clipboard.
@MainActor
final class KeyboardKeyPreferences: ObservableObject {
    static let shared = KeyboardKeyPreferences()
    @Published private(set) var snapshot: KeyboardKeySettings.Snapshot
    @Published private(set) var saveError: String?
    private let settings: KeyboardKeySettings

    init(settings: KeyboardKeySettings = .shared) {
        self.settings = settings
        let loaded = settings.loadForEditing()
        snapshot = loaded ?? .defaults
        if loaded == nil { saveError = Self.readError }
    }

    func refresh() {
        guard let value = settings.loadForEditing() else { saveError = Self.readError; return }
        if snapshot != value { snapshot = value }
        saveError = nil
    }

    @discardableResult
    func save(_ candidates: [String]?, keyID: String, gesture: KeyboardKeySettings.Gesture,
              replacing original: [String]?) -> Bool {
        guard let current = settings.loadForEditing() else { saveError = Self.readError; return false }
        guard Self.exact(current.candidates(for: keyID, gesture: gesture), original) else {
            saveError = "This key changed while you were editing. Go back and reopen it before saving."
            return false
        }
        guard let updated = current.updating(candidates, for: keyID, gesture: gesture) else {
            saveError = gesture.maximumChoices == 1 ? "Use one nonempty tap output, no longer than 64 Unicode scalars." : "Use up to 16 different, nonempty choices, each no longer than 64 Unicode scalars."
            return false
        }
        return persist(updated)
    }

    /// Saves a layout's main keyboard arrangement; nil restores its standard rows.
    @discardableResult
    func saveArrangement(_ arrangement: MainKeyboardArrangement?, alphabetID: String) -> Bool {
        guard let current = settings.loadForEditing() else { saveError = Self.readError; return false }
        guard let updated = current.updatingArrangement(arrangement, for: alphabetID) else {
            saveError = "This arrangement could not be saved."
            return false
        }
        return persist(updated)
    }

    /// Before a layout is added: it types the stock number row, whatever was
    /// saved for it. Saves only when that changes something. An unreadable
    /// file is left alone, since the keyboard then types the standard rows.
    @discardableResult
    func useStockNumberRow(alphabetID: String) -> Bool {
        guard let current = settings.loadForEditing() else { return true }
        guard let updated = current.withStockNumberRow(for: alphabetID) else {
            saveError = "This arrangement could not be saved."
            return false
        }
        return updated == current || persist(updated)
    }

    /// Saves several layers of one key as one change, such as a candidate
    /// moved from one layer to another.
    @discardableResult
    func save(layers: [KeyboardKeySettings.Gesture: [String]?], keyID: String) -> Bool {
        guard let current = settings.loadForEditing() else { saveError = Self.readError; return false }
        var updated: KeyboardKeySettings.Snapshot? = current
        for (gesture, values) in layers { updated = updated?.updating(values, for: keyID, gesture: gesture) }
        guard let updated else {
            saveError = "Use up to 16 different, nonempty choices, each no longer than 64 Unicode scalars."
            return false
        }
        return persist(updated)
    }

    @discardableResult
    func reset(keyID: String) -> Bool {
        guard KeyboardKeySettings.descriptor(for: keyID) != nil else {
            saveError = "This key is unavailable."
            return false
        }
        guard let current = settings.loadForEditing() else { saveError = Self.readError; return false }
        return persist(current.removingOverride(for: keyID))
    }

    @discardableResult
    func resetAll() -> Bool { persist(.defaults) }

    private static let readError = "Couldn’t read your saved keyboard keys. Please try again. Restore All Key Defaults in Keyboard → Symbol Keys only if you want to replace the saved configuration."

    private func persist(_ value: KeyboardKeySettings.Snapshot) -> Bool {
        guard settings.save(value) else {
            saveError = "Couldn’t save keyboard keys. Your previous settings are unchanged. Please try again."
            return false
        }
        if snapshot != value { snapshot = value }
        saveError = nil
        return true
    }

    private static func exact(_ lhs: [String]?, _ rhs: [String]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (a?, b?):
            return a.count == b.count && zip(a, b).allSatisfy { $0.utf16.elementsEqual($1.utf16) }
        default: return false
        }
    }
}
