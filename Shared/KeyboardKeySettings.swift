import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Explicit app-authored key choices. The keyboard only reads this fixed file;
/// host text, query text and transient typing state are never stored here.
struct KeyboardKeySettings {
    enum Gesture: String, CaseIterable, Codable, Sendable { case longPress, swipeUp, swipeDown }
    enum Kind: String, Sendable { case letter, digit, character, utility }
    struct Descriptor: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let text: String?
        let kind: Kind
    }

    struct Overrides: Codable, Equatable, Sendable {
        let longPress: [String]?
        let swipeUp: [String]?
        let swipeDown: [String]?

        init(longPress: [String]? = nil, swipeUp: [String]? = nil, swipeDown: [String]? = nil) {
            self.longPress = longPress; self.swipeUp = swipeUp; self.swipeDown = swipeDown
        }
        /// nil means the system default; an explicit empty list disables it.
        func candidates(for gesture: Gesture) -> [String]? {
            switch gesture { case .longPress: return longPress; case .swipeUp: return swipeUp; case .swipeDown: return swipeDown }
        }
        fileprivate var usesDefaults: Bool { longPress == nil && swipeUp == nil && swipeDown == nil }
        fileprivate func replacing(_ values: [String]?, for gesture: Gesture) -> Overrides {
            switch gesture {
            case .longPress: return .init(longPress: values, swipeUp: swipeUp, swipeDown: swipeDown)
            case .swipeUp: return .init(longPress: longPress, swipeUp: values, swipeDown: swipeDown)
            case .swipeDown: return .init(longPress: longPress, swipeUp: swipeUp, swipeDown: values)
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
        private enum CodingKeys: String, CodingKey { case longPress, swipeUp, swipeDown }
        init(from decoder: Decoder) throws {
            try KeyboardKeySettings.allowKeys(decoder, ["longPress", "swipeUp", "swipeDown"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(longPress: try c.decodeIfPresent([String].self, forKey: .longPress),
                      swipeUp: try c.decodeIfPresent([String].self, forKey: .swipeUp),
                      swipeDown: try c.decodeIfPresent([String].self, forKey: .swipeDown))
            try KeyboardKeySettings.validate(self)
        }
        func encode(to encoder: Encoder) throws {
            try KeyboardKeySettings.validate(self)
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(longPress, forKey: .longPress)
            try c.encodeIfPresent(swipeUp, forKey: .swipeUp)
            try c.encodeIfPresent(swipeDown, forKey: .swipeDown)
        }
    }

    struct Snapshot: Codable, Equatable, Sendable {
        let overrides: [String: Overrides]
        static let defaults = Snapshot()
        init(overrides: [String: Overrides] = [:]) { self.overrides = overrides }
        func candidates(for keyID: String, gesture: Gesture) -> [String]? { overrides[keyID]?.candidates(for: gesture) }
        /// The editor prepares a value first, then publishes it only if save succeeds.
        func updating(_ candidates: [String]?, for keyID: String, gesture: Gesture) -> Snapshot? {
            guard KeyboardKeySettings.descriptor(for: keyID) != nil else { return nil }
            var copy = overrides
            let value = (copy[keyID] ?? Overrides()).replacing(candidates, for: gesture)
            if value.usesDefaults { copy.removeValue(forKey: keyID) } else { copy[keyID] = value }
            let result = Snapshot(overrides: copy)
            guard (try? KeyboardKeySettings.validate(result)) != nil else { return nil }
            return result
        }
        func removingOverride(for keyID: String) -> Snapshot {
            var copy = overrides; copy.removeValue(forKey: keyID)
            return Snapshot(overrides: copy)
        }
        private enum CodingKeys: String, CodingKey { case schemaVersion, overrides }
        init(from decoder: Decoder) throws {
            try KeyboardKeySettings.allowKeys(decoder, ["schemaVersion", "overrides"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard try c.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Invalid.settings }
            let entries = try c.decode([Entry].self, forKey: .overrides)
            guard entries.count <= KeyboardKeySettings.descriptors.count else { throw Invalid.settings }
            var result: [String: Overrides] = [:]
            for entry in entries {
                guard result.updateValue(entry.values, forKey: entry.keyID) == nil else { throw Invalid.settings }
            }
            self.init(overrides: result)
            try KeyboardKeySettings.validate(self)
        }
        func encode(to encoder: Encoder) throws {
            try KeyboardKeySettings.validate(self)
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(1, forKey: .schemaVersion)
            let entries = overrides.sorted { $0.key < $1.key }.map { Entry(keyID: $0.key, values: $0.value) }
            try c.encode(entries, forKey: .overrides)
        }
    }

    /// Entries are an array on disk so duplicate IDs cannot silently overwrite
    /// one another as they would in a decoded JSON dictionary.
    private struct Entry: Codable {
        let keyID: String
        let values: Overrides
        private enum CodingKeys: String, CodingKey { case keyID, longPress, swipeUp, swipeDown }
        init(keyID: String, values: Overrides) { self.keyID = keyID; self.values = values }
        init(from decoder: Decoder) throws {
            try KeyboardKeySettings.allowKeys(decoder, ["keyID", "longPress", "swipeUp", "swipeDown"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            keyID = try c.decode(String.self, forKey: .keyID)
            values = Overrides(longPress: try c.decodeIfPresent([String].self, forKey: .longPress),
                               swipeUp: try c.decodeIfPresent([String].self, forKey: .swipeUp),
                               swipeDown: try c.decodeIfPresent([String].self, forKey: .swipeDown))
            try KeyboardKeySettings.validate(values)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(keyID, forKey: .keyID)
            try c.encodeIfPresent(values.longPress, forKey: .longPress)
            try c.encodeIfPresent(values.swipeUp, forKey: .swipeUp)
            try c.encodeIfPresent(values.swipeDown, forKey: .swipeDown)
        }
    }

    static let groupIdentifier = UnicodeEditionSettings.groupIdentifier
    static let filename = "keyboard-keys-v1.json"
    static let maximumPayloadBytes = 256 * 1024
    static let shared = KeyboardKeySettings()

    static let descriptors: [Descriptor] = {
        let letters = Array("abcdefghijklmnopqrstuvwxyz").map { Descriptor(id: "letter.\($0)", title: String($0).uppercased(), text: String($0), kind: .letter) }
        let digits = Array("0123456789").map { Descriptor(id: "digit.\($0)", title: String($0), text: String($0), kind: .digit) }
        // These are physical core/auxiliary keys, not the optional variants.
        let texts = KeyboardTypingLayout.allCases.flatMap { layout in
            layout.rows.flatMap { $0 } + KeyboardTypingLayoutPolicy.auxiliaryRow(for: layout)
                + KeyboardTypingLayoutPolicy.rows(for: layout, hasAuxiliaryRow: true).flatMap { $0 }
        }
        let symbols = Set(texts.filter { $0.unicodeScalars.count == 1 && !$0.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) } })
            .sorted { $0.unicodeScalars.first!.value < $1.unicodeScalars.first!.value }
            .map { text in Descriptor(id: String(format: "symbol.%04X", text.unicodeScalars.first!.value), title: text, text: text, kind: .character) }
        let utilities = [("space", "Space"), ("return", "Return"), ("delete", "Backspace"), ("shift", "Shift"),
                         ("layout", "123 / #+="), ("unicode", "Unicode"), ("favorites", "Favorites"), ("collapse", "Collapse")]
            .map { Descriptor(id: "utility." + $0.0, title: $0.1, text: nil, kind: .utility) }
        return letters + digits + symbols + utilities
    }()
    private static let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    static func descriptor(for keyID: String) -> Descriptor? { descriptorsByID[keyID] }
    static func identifier(forCharacter text: String) -> String? {
        guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else { return nil }
        let value = scalar.value
        if (65...90).contains(value) { return "letter." + String(Unicode.Scalar(value + 32)!) }
        if (97...122).contains(value) { return "letter." + text }
        if (48...57).contains(value) { return "digit." + text }
        let id = String(format: "symbol.%04X", value)
        return descriptorsByID[id] == nil ? nil : id
    }

    typealias ContainerProvider = () -> URL?
    typealias PrefixReader = (URL, Int) throws -> Data
    typealias AtomicWriter = (Data, URL) throws -> Void
    private let containerURL: ContainerProvider
    private let readPrefix: PrefixReader
    private let writeAtomically: AtomicWriter
    init(containerURL: @escaping ContainerProvider = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KeyboardKeySettings.groupIdentifier)
    }, readPrefix: @escaping PrefixReader = KeyboardKeySettings.readFilePrefix,
         writeAtomically: @escaping AtomicWriter = KeyboardKeySettings.writeFileAtomically) {
        self.containerURL = containerURL; self.readPrefix = readPrefix; self.writeAtomically = writeAtomically
    }
    func loadSnapshot() -> Snapshot {
        loadForEditing() ?? .defaults
    }
    /// A merge requires trustworthy existing state. Only an explicitly missing
    /// file is an editable empty configuration; malformed/unreadable data is
    /// retained until the app's separately confirmed reset-all action.
    func loadForEditing() -> Snapshot? {
        guard let container = containerURL(), container.isFileURL else { return nil }
        let data: Data
        do { data = try readPrefix(container.appendingPathComponent(Self.filename), Self.maximumPayloadBytes + 1) }
        catch {
            let error = error as NSError
            let missing = error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
                || error.domain == NSCocoaErrorDomain && error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
            return missing ? .defaults : nil
        }
        guard !data.isEmpty, data.count <= Self.maximumPayloadBytes,
              let result = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return result
    }
    /// No in-memory preference is mutated. The caller retains its prior value
    /// on false; only the containing app invokes this atomic writer.
    @discardableResult func save(_ snapshot: Snapshot) -> Bool {
        guard let container = containerURL(), container.isFileURL else { return false }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot), data.count <= Self.maximumPayloadBytes else { return false }
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
        for candidates in Gesture.allCases.compactMap({ values.candidates(for: $0) }) {
            guard candidates.count <= KeyboardVariantPolicy.maximumVariants else { throw Invalid.settings }
            var seen: Set<[UInt16]> = []
            for text in candidates {
                guard KeyboardVariantPolicy.validText(text), seen.insert(Array(text.utf16)).inserted else { throw Invalid.settings }
            }
        }
    }
    private static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.overrides.count <= descriptors.count else { throw Invalid.settings }
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
