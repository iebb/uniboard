import Foundation

enum KeyboardTypingLayout: CaseIterable {
    case letters, numbers, symbols

    var rows: [[String]] {
        switch self {
        case .letters:
            return [Array("qwertyuiop").map(String.init),
                    Array("asdfghjkl").map(String.init),
                    Array("zxcvbnm").map(String.init)]
        case .numbers:
            return [Array("1234567890").map(String.init),
                    ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
                    [".", ",", "?", "!", "'"]]
        case .symbols:
            return [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                    ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
                    [".", ",", "?", "!", "'"]]
        }
    }
}

enum KeyboardShiftState {
    case lowercase, uppercase, capsLock
}

/// Normal typing has its own transient state; Unicode query editing never
/// reads or changes the receiving document through this policy.
struct KeyboardTypingState: Equatable {
    private(set) var layout: KeyboardTypingLayout = .letters
    private(set) var shift: KeyboardShiftState = .lowercase
    private var lastShiftTap: TimeInterval?
    private var manualShiftOverride = false
    static let capsLockTapInterval: TimeInterval = 0.35

    func label(for key: String) -> String {
        layout == .letters && shift != .lowercase ? key.uppercased() : key
    }

    /// Reject stale page buttons and arbitrary strings before inserting them.
    func output(for key: String) -> String? {
        guard layout.rows.contains(where: { $0.contains(key) }) else { return nil }
        return label(for: key)
    }

    mutating func selectLayout(_ layout: KeyboardTypingLayout) {
        self.layout = layout
        resetTapSequence()
    }

    mutating func pressShift(at timestamp: TimeInterval) {
        guard layout == .letters else { resetTapSequence(); return }
        manualShiftOverride = true
        if shift == .capsLock {
            shift = .lowercase
            resetTapSequence()
            return
        }
        let validTimestamp = timestamp.isFinite && timestamp >= 0
        let elapsed = lastShiftTap.map { timestamp - $0 }
        let doubleTap = validTimestamp && elapsed.map {
            $0.isFinite && $0 >= 0 && $0 <= Self.capsLockTapInterval
        } == true
        if doubleTap {
            shift = .capsLock
            resetTapSequence()
        } else {
            shift = shift == .lowercase ? .uppercase : .lowercase
            lastShiftTap = validTimestamp ? timestamp : nil
        }
    }

    /// Dedicated iPad Caps Lock never depends on double-tap timing.
    mutating func toggleCapsLock() {
        resetTapSequence()
        guard layout == .letters else { return }
        manualShiftOverride = true
        shift = shift == .capsLock ? .lowercase : .capsLock
    }

    /// Call only after the guarded insertion succeeds. Merely rendering a key
    /// or rejecting an old button must not consume one-shot capitalization.
    mutating func didInsertKey(_ key: String) {
        guard output(for: key) != nil else { return }
        resetTapSequence()
        if layout == .letters {
            manualShiftOverride = false
            if shift == .uppercase { shift = .lowercase }
        }
    }

    mutating func resetTapSequence() { lastShiftTap = nil }

    /// A literal flick does not consume or recompute the current Shift choice.
    /// Treat it as an explicit case hint until the next ordinary edit.
    mutating func didInsertLiteralGesture() {
        manualShiftOverride = true
        resetTapSequence()
    }

    mutating func synchronizeAutomaticCapitalization(_ uppercase: Bool) {
        guard layout == .letters, shift != .capsLock, !manualShiftOverride else { return }
        shift = uppercase ? .uppercase : .lowercase
    }

    /// A space, deletion or document change begins a fresh capitalization
    /// decision. It never disables an explicitly locked Shift state.
    mutating func didEditText() {
        manualShiftOverride = false
        resetTapSequence()
    }
}

/// Identity and case at the start of one literal host write. A callback from
/// that write may preserve case only while every part of this scope matches.
struct KeyboardLiteralWriteScope: Equatable {
    let typingState: KeyboardTypingState
    let documentIdentifier: UUID
    let modeIdentifier: UUID
    let interactionIdentifier: UUID
}

/// Owns only the synchronous interval around a literal insertion. There are no
/// callbacks inside this value, so callers can release its mutation before
/// invoking the document proxy and safely consult it from reentrant callbacks.
struct KeyboardLiteralWriteTransaction {
    private struct Active {
        let token: UUID
        let scope: KeyboardLiteralWriteScope
    }
    private var active: Active?

    mutating func begin(scope: KeyboardLiteralWriteScope) -> UUID? {
        guard active == nil else { return nil }
        let token = UUID()
        active = Active(token: token, scope: scope)
        return token
    }

    /// A mismatch is terminal: returning to an earlier case or document cannot
    /// revive an old write after a newer interaction has been observed.
    mutating func matches(scope: KeyboardLiteralWriteScope?) -> Bool {
        guard let active else { return false }
        guard active.scope == scope else {
            self.active = nil
            return false
        }
        return true
    }

    /// Only the owning write may finish. The caller applies the literal case
    /// hint only when this returns true; failed or superseded writes do nothing.
    mutating func finish(token: UUID, accepted: Bool, scope: KeyboardLiteralWriteScope?) -> Bool {
        guard let active, active.token == token else { return false }
        self.active = nil
        return accepted && active.scope == scope
    }

    mutating func invalidate(token: UUID) {
        guard active?.token == token else { return }
        active = nil
    }
}
