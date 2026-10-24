import Foundation

/// In Unicode search a tap on a character key edits the local query, exactly
/// as before. Holding the same key past the keyboard's hold threshold types
/// that key's character into the host document once, and the release then
/// does nothing: no repeat and no extra query character.
///
/// The host text is what the key displays. Query keys have no Shift: they
/// always show and type their own lowercase letter, digit or punctuation
/// mark, whatever the English layer's Shift or caps lock state is, so a hold
/// inserts that literal title unchanged (no automatic capitals). Function
/// keys (Delete, Space, Done, U, globe, 123) are not query character keys and
/// keep their own behavior; Delete still repeats while held.
enum KeyboardQueryHoldPolicy {
    /// The same hold delay the rest of the keyboard uses.
    static let holdThreshold: TimeInterval = 0.4
    /// Movement from touch-down, in points, that still counts as a hold.
    static let allowedMovement: CGFloat = 10
    /// The VoiceOver custom action that performs the same host insert.
    static let accessibilityActionName = "Type in Text"
    /// The announcement after a held key typed into the host: "Typed t".
    /// An invisible character (a space, zero-width or other format or
    /// control character) is spoken by its title-cased name instead, such as
    /// "Typed Space"; `name` looks that up, and only for invisible text.
    static func typedAnnouncement(_ text: String, name: (String) -> String? = { _ in nil }) -> String {
        "Typed \(isInvisible(text) ? spokenName(text, name: name(text)) : text)"
    }

    private static let invisibleCategories: [Unicode.GeneralCategory] = [.control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator]

    /// Whether every scalar of `text` draws nothing a listener could hear.
    static func isInvisible(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            let properties = scalar.properties
            return properties.isWhitespace || properties.isDefaultIgnorableCodePoint
                || invisibleCategories.contains(properties.generalCategory)
        }
    }

    /// The catalog name, title-cased ("ZERO WIDTH SPACE" → "Zero Width
    /// Space"), or the code points when there is no name.
    static func spokenName(_ text: String, name: String?) -> String {
        if let name, !name.isEmpty {
            return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        }
        return text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }

    /// The query keyboard's character keys, top row first.
    static let rows: [[String]] = [
        Array("1234567890").map(String.init),
        Array("qwertyuiop").map(String.init),
        Array("asdfghjkl").map(String.init),
        KeyboardQueryPolicy.bottomRow,
    ]

    /// The literal host text a held query key types, or nil for anything
    /// that is not one of the query keyboard's character keys.
    static func hostText(forKey key: String) -> String? {
        rows.contains { $0.contains(key) } ? key : nil
    }

    /// One physical press of a query character key.
    struct Press: Equatable {
        enum Phase: Equatable {
            /// Down, before the threshold: still an ordinary tap.
            case pressing
            /// Moved too far before the threshold: the press stays a tap.
            case tapOnly
            /// The threshold fired and asked for the host insert.
            case held
            /// Released or cancelled; nothing more happens.
            case finished
        }
        enum Effect: Equatable {
            case none
            /// Type this text into the host document.
            case insertIntoHost(String)
            /// Commit the ordinary tap: edit the query as today.
            case editQuery
        }

        let hostText: String
        private(set) var phase: Phase = .pressing

        /// Nil for keys without a hold; they keep the ordinary press.
        init?(key: String) {
            guard let text = KeyboardQueryHoldPolicy.hostText(forKey: key) else { return nil }
            hostText = text
        }

        /// `distance` is from the touch-down point. Too far, or not finite,
        /// and the hold is abandoned while the tap remains.
        mutating func moved(distance: CGFloat) {
            guard phase == .pressing, !(distance.isFinite && distance <= KeyboardQueryHoldPolicy.allowedMovement) else { return }
            phase = .tapOnly
        }

        /// The hold threshold elapsed. Fires the insert at most once.
        mutating func thresholdReached() -> Effect {
            guard phase == .pressing else { return .none }
            phase = .held
            return .insertIntoHost(hostText)
        }

        /// The finger lifted; `inside` is whether the press still counts.
        mutating func released(inside: Bool) -> Effect {
            let previous = phase
            phase = .finished
            return inside && (previous == .pressing || previous == .tapOnly) ? .editQuery : .none
        }

        mutating func cancelled() { phase = .finished }
    }
}
