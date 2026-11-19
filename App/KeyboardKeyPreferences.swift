import SwiftUI

/// Only explicitly edited settings cross into the shared container. Never
/// derives a candidate from a document, search, recent item or clipboard.
@MainActor
final class KeyboardKeyPreferences: ObservableObject {
    static let shared = KeyboardKeyPreferences()
    @Published private(set) var snapshot: KeyboardKeySettings.Snapshot
    @Published private(set) var saveError: String?
    private let settings: KeyboardKeySettings
    private let location: SharedConfigurationLocation
    private var arrangementHistory = ArrangementHistory<KeyboardKeySettings.Snapshot>()
    private var arrangementContext: ArrangementPublication.Context?
    @Published private(set) var arrangementUndoAlphabetID: String?
    struct SuccessfulEdit {
        let id = UUID()
        let before: KeyboardKeySettings.Snapshot
        let after: KeyboardKeySettings.Snapshot
    }
    @Published private(set) var successfulEdit: SuccessfulEdit?
    func invalidateArrangementUndo() {
        arrangementHistory.invalidate(); arrangementContext = nil; arrangementUndoAlphabetID = nil
    }
    private func context() -> ArrangementPublication.Context? {
        location.currentDirectory().flatMap { ArrangementPublication.context(in: $0, excluding: []) }
    }
    func validateArrangementUndo() {
        guard let step = arrangementHistory.step else { return }
        guard settings.loadForEditing() == step.expectedAfter, context() == arrangementContext else {
            invalidateArrangementUndo(); return
        }
    }
    @discardableResult func undoArrangement(alphabetID: String) -> ArrangementUndoResult {
        guard let step = arrangementHistory.step, arrangementUndoAlphabetID == alphabetID else { return .invalidated }
        do {
            return try location.withWriterLock {
                guard let expectedContext = arrangementContext, context() == expectedContext,
                      settings.loadForEditing() == step.expectedAfter else {
                    invalidateArrangementUndo(); return .invalidated
                }
                guard settings.save(step.before) else { saveError = ArrangementCopy.restoreFailed; return .failed }
                snapshot = step.before; saveError = nil
                successfulEdit = .init(before: step.expectedAfter, after: step.before)
                invalidateArrangementUndo()
                return .restored
            }
        } catch { saveError = ArrangementCopy.restoreFailed; return .failed }
    }

    init(settings: KeyboardKeySettings = .shared, location: SharedConfigurationLocation = .shared) {
        self.settings = settings
        self.location = location
        let loaded = settings.loadForEditing()
        snapshot = loaded ?? settings.emptySnapshot()
        if loaded == nil { saveError = Self.readError }
    }

    func refresh() {
        guard let value = settings.loadForEditing() else { invalidateArrangementUndo(); saveError = Self.readError; return }
        if snapshot != value { snapshot = value }
        validateArrangementUndo()
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
        return persist(updated, replacing: current)
    }

    /// Saves a layout's main keyboard arrangement; nil restores its standard rows.
    @discardableResult
    func saveArrangement(_ arrangement: MainKeyboardArrangement?, alphabetID: String) -> Bool {
        guard let current = settings.loadForEditing() else { saveError = Self.readError; return false }
        guard let updated = current.updatingArrangement(arrangement, for: alphabetID) else {
            saveError = "This arrangement could not be saved."
            return false
        }
        return persist(updated, replacing: current, arrangementAlphabetID: alphabetID)
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
        return updated == current || persist(updated, replacing: current)
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
        return persist(updated, replacing: current)
    }

    @discardableResult
    func reset(keyID: String) -> Bool {
        guard KeyboardKeySettings.descriptor(for: keyID) != nil else {
            saveError = "This key is unavailable."
            return false
        }
        guard let current = settings.loadForEditing() else { saveError = Self.readError; return false }
        return persist(current.removingOverride(for: keyID), replacing: current)
    }

    @discardableResult
    func resetAll() -> Bool {
        // This separately confirmed recovery action intentionally requires no
        // merge read, including when the original file cannot be decoded.
        do {
            return try location.withWriterLock {
                guard settings.save(.defaults) else {
                    saveError = "Couldn’t save keyboard keys. Your previous settings are unchanged. Please try again."
                    return false
                }
                let before = snapshot
                let knownBefore = saveError == nil
                // The install's number row stays: Reset All restores its default keyboard.
                let reset = settings.emptySnapshot()
                if snapshot != reset || snapshot.standardNumberRow != reset.standardNumberRow { snapshot = reset }
                if knownBefore, before != reset { successfulEdit = .init(before: before, after: reset) }
                invalidateArrangementUndo(); saveError = nil
                return true
            }
        } catch {
            saveError = "Couldn’t save keyboard keys. Your previous settings are unchanged. Please try again."
            return false
        }
    }

    private static let readError = "Couldn’t read your saved keyboard keys. Try again. To reset all key actions and arrangements, open Main Keyboard in Keyboard, then choose Restore All Key Defaults from the More menu. This replaces your saved key settings."

    private func persist(_ value: KeyboardKeySettings.Snapshot,
                         replacing original: KeyboardKeySettings.Snapshot?,
                         arrangementAlphabetID: String? = nil) -> Bool {
        do {
            return try location.withWriterLock {
                let current = settings.loadForEditing()
                guard current == original, current != nil else {
                    saveError = "Your keyboard settings changed. Reopen the editor before saving."
                    invalidateArrangementUndo(); return false
                }
                if current == value {
                    if snapshot != value { snapshot = value }
                    saveError = nil; return true
                }
                guard settings.save(value) else {
                    saveError = "Couldn’t save keyboard keys. Your previous settings are unchanged. Please try again."
                    return false
                }
                if snapshot != value { snapshot = value }
                saveError = nil
                if let current { successfulEdit = .init(before: current, after: value) }
                if let arrangementAlphabetID, let current, let context = context() {
                    arrangementHistory.record(before: current, after: value, succeeded: true)
                    arrangementContext = context
                    arrangementUndoAlphabetID = arrangementAlphabetID
                } else { invalidateArrangementUndo() }
                return true
            }
        } catch {
            saveError = "Couldn’t save keyboard keys. Your previous settings are unchanged. Please try again."
            return false
        }
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
