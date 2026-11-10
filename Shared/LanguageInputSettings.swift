import Foundation

/// Versioned semantic-input preferences only. The containing app writes this
/// bounded snapshot; the keyboard reads it. Pack bytes and custom dictionaries
/// live elsewhere. No selected mode, unfinished input or history is persisted.
public struct LanguageInputSettings {
    public static let filename = "language-input-v1.json"
    public static let schemaVersion = 1
    public static let maximumPayloadBytes = 8192
    public static let maximumPackReferences = 8
    public static let shared = LanguageInputSettings()
    public static let defaultValue = Value()
    /// Stable storage/export order, independent of any UI ordering.
    public static let modeOrder: [LanguageInputMode] = [.direct, .japaneseRomaji, .mandarinPinyin, .koreanRomaja, .koreanTwoSetHangul]

    /// Release availability is presentation/runtime policy, NOT a storage migration.
    /// Keep deferred preferences and pack references intact for export and later releases.
    public static let visibleModeOrder: [LanguageInputMode] = [.direct, .japaneseRomaji, .mandarinPinyin, .koreanTwoSetHangul]
    public static let englishAssistanceAvailable = false

    /// A pinned identity, never a download instruction or resource location.
    /// A pack ID identifies one mode and one pinned version in a snapshot.
    public struct PackReference: Codable, Equatable, Sendable {
        public var mode: LanguageInputMode
        public var packID: String
        public var version: String
        public var archiveSHA256: String

        public init(mode: LanguageInputMode, packID: String, version: String, archiveSHA256: String) {
            self.mode = mode
            self.packID = packID
            self.version = version
            self.archiveSHA256 = archiveSHA256
        }

        public var isValid: Bool {
            LanguageInputSettings.modeOrder.contains(mode)
                && LanguageInputSettings.isCanonicalIdentifier(packID)
                && LanguageInputSettings.isCanonicalIdentifier(version)
                && archiveSHA256.utf8.count == 64
                && archiveSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }

        private enum CodingKeys: String, CodingKey, CaseIterable { case mode, packID, version, archiveSHA256 }

        public init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mode = try c.decode(LanguageInputMode.self, forKey: .mode)
            packID = try c.decode(String.self, forKey: .packID)
            version = try c.decode(String.self, forKey: .version)
            archiveSHA256 = try c.decode(String.self, forKey: .archiveSHA256)
            guard isValid else { throw invalidSnapshot(decoder) }
        }
    }

    public struct Value: Codable, Equatable, Sendable {
        public var enabledModes: [LanguageInputMode]
        public var englishSuggestions: Bool
        public var englishAutocorrection: Bool
        public var packReferences: [PackReference]

        public static let defaults = Value()

        public init(enabledModes: [LanguageInputMode] = [.direct], englishSuggestions: Bool = false,
                    englishAutocorrection: Bool = false, packReferences: [PackReference] = []) {
            self.enabledModes = enabledModes
            self.englishSuggestions = englishSuggestions
            self.englishAutocorrection = englishAutocorrection
            self.packReferences = packReferences
        }

        public var isValid: Bool {
            guard (1...LanguageInputSettings.modeOrder.count).contains(enabledModes.count),
                  enabledModes.first == .direct,
                  enabledModes == LanguageInputSettings.modeOrder.filter({ enabledModes.contains($0) }),
                  packReferences.count <= LanguageInputSettings.maximumPackReferences,
                  packReferences.allSatisfy(\.isValid) else { return false }
            // Reject duplicates, conflicting versions/hashes, and a pack ID
            // assigned to different modes. Pins for disabled modes are valid:
            // installing or importing a resource never enables its converter.
            return Set(packReferences.map(\.packID)).count == packReferences.count
        }

        /// Effective runtime choices never rewrite the saved independent switches.
        /// Future correction resources must remain optional and separately enabled.
        public var effectiveEnglishSuggestions: Bool {
            LanguageInputSettings.englishAssistanceAvailable && englishSuggestions
        }

        public var effectiveEnglishAutocorrection: Bool {
            LanguageInputSettings.englishAssistanceAvailable && englishAutocorrection
        }

        public func isEnabled(_ mode: LanguageInputMode) -> Bool {
            mode == .direct || enabledModes.contains(mode)
        }

        /// Returns false rather than disabling the always-available literal mode.
        @discardableResult public mutating func setEnabled(_ enabled: Bool, for mode: LanguageInputMode) -> Bool {
            guard LanguageInputSettings.modeOrder.contains(mode), mode != .direct || enabled else { return false }
            enabledModes = LanguageInputSettings.modeOrder.filter { $0 == .direct || ($0 == mode ? enabled : enabledModes.contains($0)) }
            return true
        }

        private enum CodingKeys: String, CodingKey, CaseIterable { case enabledModes, englishSuggestions, englishAutocorrection, packReferences }

        public init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabledModes = try c.decode([LanguageInputMode].self, forKey: .enabledModes)
            englishSuggestions = try c.decode(Bool.self, forKey: .englishSuggestions)
            englishAutocorrection = try c.decode(Bool.self, forKey: .englishAutocorrection)
            packReferences = try c.decode([PackReference].self, forKey: .packReferences)
            guard isValid else { throw invalidSnapshot(decoder) }
        }
    }

    private struct File: Codable {
        let schemaVersion: Int
        let value: Value
        private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, value }

        init(value: Value) { schemaVersion = LanguageInputSettings.schemaVersion; self.value = value }

        init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == LanguageInputSettings.schemaVersion else { throw invalidSnapshot(decoder) }
            value = try c.decode(Value.self, forKey: .value)
        }
    }

    public let directory: () -> URL?

    public init(directory: @escaping () -> URL?) {
        self.directory = directory
    }

    public init() {
        self.init(directory: { SharedConfigurationLocation.shared.currentDirectory() })
    }

    public func load() -> Value {
        guard let directory = directory(),
              let data = try? SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(Self.filename),
                                                                          limit: Self.maximumPayloadBytes + 1) else { return Self.defaultValue }
        return Self.decode(data) ?? Self.defaultValue
    }

    /// App only. Failure is observable and never reported as a successful save.
    @discardableResult public func save(_ value: Value) -> Bool {
        guard let directory = directory(), let data = Self.encode(value) else { return false }
        do {
            try SharedConfigurationLocation.replaceFile(data, at: directory.appendingPathComponent(Self.filename))
            return true
        } catch { return false }
    }

    public static func encode(_ value: Value) -> Data? {
        guard value.isValid, let data = try? SharedConfigurationLocation.encoder.encode(File(value: value)),
              data.count <= maximumPayloadBytes else { return nil }
        return data
    }

    public static func decode(_ data: Data) -> Value? {
        guard data.count <= maximumPayloadBytes else { return nil }
        return (try? JSONDecoder().decode(File.self, from: data))?.value
    }

    /// Canonical portable IDs: 1–128 ASCII letters/digits, with interior
    /// '.', '_' or '-'. Exact, case-sensitive identities; no paths or URLs.
    public static func isCanonicalIdentifier(_ text: String) -> Bool {
        guard (1...128).contains(text.utf8.count) else { return false }
        let bytes = Array(text.utf8)
        func alphanumeric(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) }
        guard (1...128).contains(bytes.count), let first = bytes.first, let last = bytes.last,
              alphanumeric(first), alphanumeric(last) else { return false }
        return bytes.allSatisfy { alphanumeric($0) || $0 == 45 || $0 == 46 || $0 == 95 }
    }
}

private struct LanguageInputSnapshotKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: [String]) throws {
    let c = try decoder.container(keyedBy: LanguageInputSnapshotKey.self)
    guard c.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw invalidSnapshot(decoder) }
}

private func invalidSnapshot(_ decoder: Decoder) -> DecodingError {
    // Never put untrusted settings or user input in an error or log.
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid language-input snapshot."))
}
