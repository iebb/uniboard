import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Explicit app-authored key choices. The keyboard only reads this fixed file;
/// host text, query text and transient typing state are never stored here.
struct KeyboardKeySettings {
    enum Gesture: String, CaseIterable, Codable, Sendable { case tap, shiftedTap, longPress, swipeUp, swipeDown
        var maximumChoices: Int { self == .tap || self == .shiftedTap ? 1 : KeyboardVariantPolicy.maximumVariants }
        /// The candidate layers a key can be customized with; a key's own
        /// output is changed separately with `tap`.
        static let customizable: [Gesture] = [.swipeUp, .swipeDown, .longPress]
    }
    enum Kind: String, Sendable { case letter, digit, character }
    struct Descriptor: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let text: String?
        let kind: Kind
    }

    struct Overrides: Codable, Equatable, Sendable {
        let tap: [String]?
        let shiftedTap: [String]?
        let longPress: [String]?
        let swipeUp: [String]?
        let swipeDown: [String]?

        init(tap: [String]? = nil, shiftedTap: [String]? = nil, longPress: [String]? = nil, swipeUp: [String]? = nil, swipeDown: [String]? = nil) {
            self.tap = tap; self.shiftedTap = shiftedTap
            self.longPress = longPress; self.swipeUp = swipeUp; self.swipeDown = swipeDown
        }
        /// nil means the system default; an explicit empty list disables it.
        func candidates(for gesture: Gesture) -> [String]? {
            switch gesture { case .tap: return tap; case .shiftedTap: return shiftedTap; case .longPress: return longPress; case .swipeUp: return swipeUp; case .swipeDown: return swipeDown }
        }
        fileprivate var usesDefaults: Bool { tap == nil && shiftedTap == nil && longPress == nil && swipeUp == nil && swipeDown == nil }
        fileprivate func replacing(_ values: [String]?, for gesture: Gesture) -> Overrides {
            switch gesture {
            case .tap: return .init(tap: values, shiftedTap: shiftedTap, longPress: longPress, swipeUp: swipeUp, swipeDown: swipeDown)
            case .shiftedTap: return .init(tap: tap, shiftedTap: values, longPress: longPress, swipeUp: swipeUp, swipeDown: swipeDown)
            case .longPress: return .init(tap: tap, shiftedTap: shiftedTap, longPress: values, swipeUp: swipeUp, swipeDown: swipeDown)
            case .swipeUp: return .init(tap: tap, shiftedTap: shiftedTap, longPress: longPress, swipeUp: values, swipeDown: swipeDown)
            case .swipeDown: return .init(tap: tap, shiftedTap: shiftedTap, longPress: longPress, swipeUp: swipeUp, swipeDown: values)
            }
        }
        static func == (lhs: Self, rhs: Self) -> Bool {
            Gesture.allCases.allSatisfy { gesture in
                switch (lhs.candidates(for: gesture), rhs.candidates(for: gesture)) {
                case (nil, nil): return true
                case let (a?, b?): return a.count == b.count && zip(a, b).allSatisfy { $0.utf16.elementsEqual($1.utf16) }
                default: return false
                }
            }
        }
        private enum CodingKeys: String, CodingKey { case tap, shiftedTap, longPress, swipeUp, swipeDown }
        init(from decoder: Decoder) throws {
            try KeyboardKeySettings.allowKeys(decoder, ["tap", "shiftedTap", "longPress", "swipeUp", "swipeDown"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(tap: try c.decodeIfPresent([String].self, forKey: .tap),
                      shiftedTap: try c.decodeIfPresent([String].self, forKey: .shiftedTap),
                      longPress: try c.decodeIfPresent([String].self, forKey: .longPress),
                      swipeUp: try c.decodeIfPresent([String].self, forKey: .swipeUp),
                      swipeDown: try c.decodeIfPresent([String].self, forKey: .swipeDown))
            try KeyboardKeySettings.validate(self)
        }
        func encode(to encoder: Encoder) throws {
            try KeyboardKeySettings.validate(self)
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(tap, forKey: .tap)
            try c.encodeIfPresent(shiftedTap, forKey: .shiftedTap)
            try c.encodeIfPresent(longPress, forKey: .longPress)
            try c.encodeIfPresent(swipeUp, forKey: .swipeUp)
            try c.encodeIfPresent(swipeDown, forKey: .swipeDown)
        }
    }

    struct Snapshot: Codable, Equatable, Sendable {
        let overrides: [String: Overrides]
        /// Rearranged main keyboards by layout id.
        let arrangements: [String: MainKeyboardArrangement]
        /// Whether the arrangements hold the number row (schema 4). Earlier
        /// files arranged only the letters, and Settings' Number Row added
        /// the digits above them; `migratingNumberRow` reads such a file once.
        let arrangesNumberRow: Bool
        static let defaults = Snapshot()
        init(overrides: [String: Overrides] = [:], arrangements: [String: MainKeyboardArrangement] = [:], arrangesNumberRow: Bool = true) {
            self.overrides = overrides; self.arrangements = arrangements; self.arrangesNumberRow = arrangesNumberRow
        }
        func arrangement(for alphabetID: String) -> MainKeyboardArrangement? { arrangements[alphabetID] }
        /// The layout's keyboard as it types: the saved arrangement while it
        /// is valid, otherwise the standard one with the number row.
        func effectiveArrangement(for alphabet: KeyboardAlphabet) -> MainKeyboardArrangement {
            arrangements[alphabet.id].flatMap { $0.isValid(for: alphabet) ? $0 : nil } ?? .standard(for: alphabet)
        }
        /// nil, or the standard arrangement, restores the layout's own rows.
        func updatingArrangement(_ arrangement: MainKeyboardArrangement?, for alphabetID: String) -> Snapshot? {
            guard let alphabet = KeyboardAlphabet.alphabet(id: alphabetID) else { return nil }
            var copy = arrangements
            if let arrangement, arrangement != .standard(for: alphabet) { copy[alphabetID] = arrangement }
            else { copy.removeValue(forKey: alphabetID) }
            let result = Snapshot(overrides: overrides, arrangements: copy, arrangesNumberRow: arrangesNumberRow)
            guard (try? KeyboardKeySettings.validate(result)) != nil else { return nil }
            return result
        }
        /// A layout being added types the stock number row, never digits saved
        /// for it before, such as a migrated keyboard without them. Its other
        /// saved keys stay; when the digits do not fit above them it gets the
        /// standard keyboard. Other layouts never change. nil for an unknown layout.
        func withStockNumberRow(for alphabetID: String) -> Snapshot? {
            guard let alphabet = KeyboardAlphabet.alphabet(id: alphabetID) else { return nil }
            guard let saved = arrangements[alphabetID] else { return self }
            return updatingArrangement(saved.isValid(for: alphabet) ? saved.withStockNumberRow() : nil, for: alphabetID)
        }
        /// An earlier file's arrangements with the number row they were shown
        /// with, once. With Number Row on, a layout without its own arrangement
        /// gets the standard one and a custom one gains the digits as its own
        /// first row. With it off, a custom one stays as it is and the others
        /// get the standard letters without digits. Overrides never change.
        func migratingNumberRow(showsNumberRow: Bool) -> Snapshot {
            guard !arrangesNumberRow else { return self }
            var result: [String: MainKeyboardArrangement] = [:]
            for alphabet in KeyboardAlphabet.catalog {
                let letters = MainKeyboardArrangement.letters(for: alphabet)
                let saved = arrangements[alphabet.id] ?? letters
                // Earlier files hold no digits in at most three rows, so the number row always fits on top.
                let next = showsNumberRow ? saved.prependingNumberRow : saved
                if next != .standard(for: alphabet) { result[alphabet.id] = next }
            }
            return Snapshot(overrides: overrides, arrangements: result)
        }
        func candidates(for keyID: String, gesture: Gesture) -> [String]? {
            guard KeyboardKeySettings.descriptor(for: keyID) != nil else { return nil }
            return overrides[keyID]?.candidates(for: gesture)
        }
        /// A tap types the key's own text unless the key was changed. With
        /// Shift, a changed letter types its capital and other keys their
        /// shifted text, unless a shifted value was saved too.
        func tapOutput(for keyID: String, defaultText: String, shifted: Bool) -> String? {
            guard let descriptor = KeyboardKeySettings.descriptor(for: keyID), KeyboardVariantPolicy.validText(defaultText) else { return nil }
            let values = overrides[keyID]
            if shifted, let value = values?.shiftedTap?.first { return value }
            guard let value = values?.tap?.first else { return defaultText }
            if !shifted { return value }
            return descriptor.kind == .letter ? value.uppercased() : defaultText
        }
        /// The editor prepares a value first, then publishes it only if save succeeds.
        func updating(_ candidates: [String]?, for keyID: String, gesture: Gesture) -> Snapshot? {
            guard KeyboardKeySettings.descriptor(for: keyID) != nil else { return nil }
            var copy = overrides
            let value = (copy[keyID] ?? Overrides()).replacing(candidates, for: gesture)
            if value.usesDefaults { copy.removeValue(forKey: keyID) } else { copy[keyID] = value }
            let result = Snapshot(overrides: copy, arrangements: arrangements, arrangesNumberRow: arrangesNumberRow)
            guard (try? KeyboardKeySettings.validate(result)) != nil else { return nil }
            return result
        }
        func removingOverride(for keyID: String) -> Snapshot {
            var copy = overrides; copy.removeValue(forKey: keyID)
            return Snapshot(overrides: copy, arrangements: arrangements, arrangesNumberRow: arrangesNumberRow)
        }
        private enum CodingKeys: String, CodingKey { case schemaVersion, overrides, arrangements }
        init(from decoder: Decoder) throws {
            try KeyboardKeySettings.allowKeys(decoder, ["schemaVersion", "overrides", "arrangements"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let schema = try c.decode(Int.self, forKey: .schemaVersion)
            guard (1...4).contains(schema), schema >= 3 || !c.contains(.arrangements) else { throw Invalid.settings }
            let entries = try c.decode([Entry].self, forKey: .overrides)
            guard entries.count <= KeyboardKeySettings.descriptors.count + KeyboardKeySettings.legacyFunctionKeyIDs.count else { throw Invalid.settings }
            var seen = Set<String>()
            var result: [String: Overrides] = [:]
            for entry in entries {
                guard schema != 1 || !entry.includesTapFields else { throw Invalid.settings }
                guard seen.insert(entry.keyID).inserted else { throw Invalid.settings }
                // Earlier 1.1 betas offered function-key overrides. Retire only
                // those exact IDs without discarding valid character settings.
                // Reading never rewrites the shared file; the next app save
                // persists just the supported keys. Malformed entries still fail.
                if !KeyboardKeySettings.legacyFunctionKeyIDs.contains(entry.keyID) {
                    result[entry.keyID] = entry.values
                }
            }
            self.init(overrides: result, arrangements: try c.decodeIfPresent([String: MainKeyboardArrangement].self, forKey: .arrangements) ?? [:],
                      arrangesNumberRow: schema == 4)
            try KeyboardKeySettings.validate(self)
        }
        func encode(to encoder: Encoder) throws {
            try KeyboardKeySettings.validate(self)
            var c = encoder.container(keyedBy: CodingKeys.self)
            // An earlier file that was never migrated keeps its own meaning.
            try c.encode(arrangesNumberRow ? 4 : 3, forKey: .schemaVersion)
            let entries = overrides.sorted { $0.key < $1.key }.map { Entry(keyID: $0.key, values: $0.value) }
            try c.encode(entries, forKey: .overrides)
            if !arrangements.isEmpty { try c.encode(arrangements, forKey: .arrangements) }
        }
    }

    /// Entries are an array on disk so duplicate IDs cannot silently overwrite
    /// one another as they would in a decoded JSON dictionary.
    private struct Entry: Codable {
        let keyID: String
        let values: Overrides
        let includesTapFields: Bool
        private enum CodingKeys: String, CodingKey { case keyID, tap, shiftedTap, longPress, swipeUp, swipeDown }
        init(keyID: String, values: Overrides) {
            self.keyID = keyID; self.values = values
            includesTapFields = values.tap != nil || values.shiftedTap != nil
        }
        init(from decoder: Decoder) throws {
            try KeyboardKeySettings.allowKeys(decoder, ["keyID", "tap", "shiftedTap", "longPress", "swipeUp", "swipeDown"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            keyID = try c.decode(String.self, forKey: .keyID)
            includesTapFields = c.contains(.tap) || c.contains(.shiftedTap)
            values = Overrides(tap: try c.decodeIfPresent([String].self, forKey: .tap),
                               shiftedTap: try c.decodeIfPresent([String].self, forKey: .shiftedTap),
                               longPress: try c.decodeIfPresent([String].self, forKey: .longPress),
                               swipeUp: try c.decodeIfPresent([String].self, forKey: .swipeUp),
                               swipeDown: try c.decodeIfPresent([String].self, forKey: .swipeDown))
            try KeyboardKeySettings.validate(values)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(keyID, forKey: .keyID)
            try c.encodeIfPresent(values.tap, forKey: .tap)
            try c.encodeIfPresent(values.shiftedTap, forKey: .shiftedTap)
            try c.encodeIfPresent(values.longPress, forKey: .longPress)
            try c.encodeIfPresent(values.swipeUp, forKey: .swipeUp)
            try c.encodeIfPresent(values.swipeDown, forKey: .swipeDown)
        }
    }

    static let groupIdentifier = UnicodeEditionSettings.groupIdentifier
    static let filename = "keyboard-keys-v1.json"
    static let maximumPayloadBytes = 256 * 1024
    static let shared = KeyboardKeySettings()
    private static let legacyFunctionKeyIDs: Set<String> = [
        "utility.space", "utility.return", "utility.delete", "utility.shift",
        "utility.layout", "utility.unicode", "utility.favorites", "utility.collapse"
    ]

    static let descriptors: [Descriptor] = {
        let ascii = Array("abcdefghijklmnopqrstuvwxyz").map { Descriptor(id: "letter.\($0)", title: String($0).uppercased(), text: String($0), kind: .letter) }
        // Letters of the other layouts. ASCII letters keep their original IDs;
        // the rest are named by their lowercase scalar, such as letter.03B1.
        var seen = Set(ascii.compactMap(\.text))
        let international = KeyboardAlphabet.catalog.flatMap { alphabet in
            alphabet.keys.compactMap { key -> Descriptor? in
                guard alphabet.isCasedLetter(key), key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first,
                      seen.insert(key).inserted else { return nil }
                return Descriptor(id: String(format: "letter.%04X", scalar.value), title: alphabet.uppercase(key), text: key, kind: .letter)
            }
        }
        let letters = ascii + international
        let digits = Array("0123456789").map { Descriptor(id: "digit.\($0)", title: String($0), text: String($0), kind: .digit) }
        // These are physical core/auxiliary keys, not the optional variants.
        let texts = KeyboardTypingLayout.allCases.flatMap { layout in
            layout.rows.flatMap { $0 } + KeyboardTypingLayoutPolicy.auxiliaryRow(for: layout)
                + KeyboardTypingLayoutPolicy.auxiliaryRow(for: layout, ansiPad: true)
                + KeyboardTypingLayoutPolicy.rows(for: layout, hasAuxiliaryRow: true, widePad: true, ansiPad: true).flatMap { $0 }
        }
        let symbols = Set(texts.filter { $0.unicodeScalars.count == 1 && !$0.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) } })
            .sorted { $0.unicodeScalars.first!.value < $1.unicodeScalars.first!.value }
            .map { text in Descriptor(id: String(format: "symbol.%04X", text.unicodeScalars.first!.value), title: text, text: text, kind: .character) }
        return letters + digits + symbols
    }()
    private static let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    static func descriptor(for keyID: String) -> Descriptor? { descriptorsByID[keyID] }
    /// Non-ASCII letters and capitals in every layout, such as Turkish İ for
    /// the i key. A capital that is ASCII, like Turkish I, keeps the ASCII
    /// key's settings; one that lowercases to another key, like Σ for ς,
    /// belongs to that key.
    private static let internationalLetterIDs: [String: String] = {
        var ids: [String: String] = [:]
        for descriptor in descriptors where descriptor.kind == .letter && descriptor.id.count > "letter.x".count {
            if let text = descriptor.text { ids[text] = descriptor.id }
        }
        for alphabet in KeyboardAlphabet.catalog {
            for key in alphabet.keys {
                let capital = alphabet.uppercase(key)
                let ascii = key.count == 1 && key.allSatisfy { ("a"..."z").contains($0) } ? "letter." + key : nil
                guard let id = ids[key] ?? ascii, ids[capital] == nil,
                      capital.unicodeScalars.count == 1, !capital.unicodeScalars.allSatisfy(\.isASCII),
                      alphabet.lowercase(capital) == key else { continue }
                ids[capital] = id
            }
        }
        return ids
    }()
    static func identifier(forCharacter text: String) -> String? {
        guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else { return nil }
        let value = scalar.value
        if (65...90).contains(value) { return "letter." + String(Unicode.Scalar(value + 32)!) }
        if (97...122).contains(value) { return "letter." + text }
        if (48...57).contains(value) { return "digit." + text }
        if let id = internationalLetterIDs[text] { return id }
        let id = String(format: "symbol.%04X", value)
        return descriptorsByID[id] == nil ? nil : id
    }

    typealias ContainerProvider = () -> URL?
    typealias PrefixReader = (URL, Int) throws -> Data
    typealias AtomicWriter = (Data, URL) throws -> Void
    /// The retired Settings Number Row choice stored beside this file in a
    /// directory; read only while this file has not been migrated.
    typealias NumberRowReader = (URL) -> Bool
    private let containerURL: ContainerProvider
    private let readPrefix: PrefixReader
    private let writeAtomically: AtomicWriter
    private let legacyShowsNumberRow: NumberRowReader
    /// The default reads the current shared configuration generation, or
    /// the group root before migration.
    init(containerURL: @escaping ContainerProvider = {
        SharedConfigurationLocation.shared.currentDirectory()
    }, readPrefix: @escaping PrefixReader = KeyboardKeySettings.readFilePrefix,
         writeAtomically: @escaping AtomicWriter = KeyboardKeySettings.writeFileAtomically,
         legacyShowsNumberRow: @escaping NumberRowReader = { directory in
        UnicodeEditionSettings(containerURL: { directory }).loadSnapshot().showsNumberRow
    }) {
        self.containerURL = containerURL; self.readPrefix = readPrefix; self.writeAtomically = writeAtomically
        self.legacyShowsNumberRow = legacyShowsNumberRow
    }
    func loadSnapshot() -> Snapshot {
        loadForEditing() ?? .defaults
    }
    /// A merge requires trustworthy existing state. Only an explicitly missing
    /// file is an editable empty configuration; malformed/unreadable data is
    /// retained until the app's separately confirmed reset-all action. An
    /// earlier file, or none, is read with the number row it was shown with.
    func loadForEditing() -> Snapshot? {
        guard let container = containerURL(), container.isFileURL, let stored = loadStored(in: container) else { return nil }
        return stored.arrangesNumberRow ? stored : stored.migratingNumberRow(showsNumberRow: legacyShowsNumberRow(container))
    }
    /// Saves the number row migration once, so the retired Number Row choice
    /// is never read again. True when it saved; false when there was nothing
    /// to migrate or the file is unreadable, which is never replaced here.
    @discardableResult func migrateNumberRowIfNeeded() -> Bool {
        guard let container = containerURL(), container.isFileURL, let stored = loadStored(in: container),
              !stored.arrangesNumberRow else { return false }
        return save(stored.migratingNumberRow(showsNumberRow: legacyShowsNumberRow(container)))
    }
    private func loadStored(in container: URL) -> Snapshot? {
        let data: Data
        do { data = try readPrefix(container.appendingPathComponent(Self.filename), Self.maximumPayloadBytes + 1) }
        catch {
            let error = error as NSError
            let missing = error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
                || error.domain == NSCocoaErrorDomain && error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
            return missing ? Snapshot(arrangesNumberRow: false) : nil
        }
        return Self.decode(data)
    }
    /// nil when the payload is empty, oversized or invalid.
    static func decode(_ data: Data) -> Snapshot? {
        guard !data.isEmpty, data.count <= maximumPayloadBytes,
              let result = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return result
    }
    /// The store's own encoding (sorted keys); nil over the size cap.
    static func encode(_ snapshot: Snapshot) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot), data.count <= maximumPayloadBytes else { return nil }
        return data
    }
    /// No in-memory preference is mutated. The caller retains its prior value
    /// on false; only the containing app invokes this atomic writer.
    @discardableResult func save(_ snapshot: Snapshot) -> Bool {
        guard let container = containerURL(), container.isFileURL, let data = Self.encode(snapshot) else { return false }
        do { try writeAtomically(data, container.appendingPathComponent(Self.filename)); return true }
        catch { return false }
    }
    @discardableResult func reset() -> Bool { save(.defaults) }

    private enum Invalid: Error { case settings, file }
    /// The standard dictionary decoder exposes every string key. Values are
    /// decoded with their real types immediately after this strict name check.
    private struct FieldPresence: Decodable {
        init(from decoder: Decoder) {}
    }
    private static func allowKeys(_ decoder: Decoder, _ allowed: Set<String>) throws {
        let fields = try [String: FieldPresence](from: decoder)
        guard Set(fields.keys).isSubset(of: allowed) else { throw Invalid.settings }
    }
    private static func validate(_ values: Overrides) throws {
        for gesture in Gesture.allCases {
            guard let candidates = values.candidates(for: gesture) else { continue }
            guard candidates.count <= gesture.maximumChoices else { throw Invalid.settings }
            var seen: Set<[UInt16]> = []
            for text in candidates {
                guard KeyboardVariantPolicy.validText(text), seen.insert(Array(text.utf16)).inserted else { throw Invalid.settings }
            }
        }
    }
    private static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.overrides.count <= descriptors.count else { throw Invalid.settings }
        for (alphabetID, arrangement) in snapshot.arrangements {
            guard let alphabet = KeyboardAlphabet.alphabet(id: alphabetID), arrangement.isValid(for: alphabet),
                  snapshot.arrangesNumberRow || arrangement.isLetterOnly else { throw Invalid.settings }
        }
        for (keyID, values) in snapshot.overrides {
            guard descriptorsByID[keyID] != nil else { throw Invalid.settings }
            try validate(values)
        }
    }
    private static func readFilePrefix(_ url: URL, maximumBytes: Int) throws -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { errno = EINVAL; return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw Invalid.file }
        var data = Data()
        while data.count < maximumBytes {
            let chunk = try handle.read(upToCount: maximumBytes - data.count) ?? Data()
            if chunk.isEmpty { break }; data.append(chunk)
        }
        return data
    }
    private static func writeFileAtomically(_ data: Data, to url: URL) throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw Invalid.file }
        try data.write(to: url, options: [.atomic])
    }
}
