import Foundation

/// The saved font rules: the app's source of truth for rules, kept as JSON
/// in the current configuration generation. TOML is only the exchange
/// format; the keyboard reads this compiled snapshot and never parses TOML.
struct FontRuleStore {
    static let filename = "font-rules-v1.json"
    /// 1,024 rules with long face names fit; more is refused, never trimmed.
    static let maximumPayloadBytes = 1024 * 1024
    static let shared = FontRuleStore()

    let directory: () -> URL?

    init(directory: @escaping () -> URL? = { SharedConfigurationLocation.shared.currentDirectory() }) {
        self.directory = directory
    }

    private struct File: Codable {
        let schemaVersion: Int
        let rules: [Stored]
    }

    /// Exactly one of `codePoint`, `range` or `block`.
    private struct Stored: Codable {
        var id: String
        var codePoint: UInt32?
        var range: [UInt32]?
        var block: FontRuleBlock?
        var face: FontFaceReference

        init(_ rule: FontRule) {
            id = rule.id
            face = rule.face
            switch rule.selector {
            case let .codePoint(value): codePoint = value
            case let .range(first, last): range = [first, last]
            case let .block(value): block = value
            }
        }

        var rule: FontRule? {
            switch (codePoint, range, block) {
            case let (value?, nil, nil): return FontRule(id: id, selector: .codePoint(value), face: face)
            case let (nil, bounds?, nil) where bounds.count == 2: return FontRule(id: id, selector: .range(first: bounds[0], last: bounds[1]), face: face)
            case let (nil, nil, value?): return FontRule(id: id, selector: .block(value), face: face)
            default: return nil
            }
        }
    }

    /// [] when no rules were saved; nil when the file can't be used. An
    /// unusable file is kept as it is, never repaired. Without a block table
    /// (the keyboard), block rules are checked for shape only.
    func load(blocks: [UnicodeBlock]? = nil) -> [FontRule]? {
        guard let directory = directory() else { return nil }
        do {
            guard let data = try SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent(Self.filename),
                                                                             limit: Self.maximumPayloadBytes + 1) else { return [] }
            return Self.decode(data, blocks: blocks)
        } catch { return nil }
    }

    /// Only the containing app saves. Rules that don't validate against the
    /// full block table are refused, never trimmed.
    @discardableResult func save(_ rules: [FontRule], blocks: [UnicodeBlock] = UnicodeCatalog.shared.blocks) -> Bool {
        guard let directory = directory(), let data = Self.encode(rules, blocks: blocks),
              (try? SharedConfigurationLocation.replaceFile(data, at: directory.appendingPathComponent(Self.filename))) != nil else { return false }
        return true
    }

    static func encode(_ rules: [FontRule], blocks: [UnicodeBlock]? = nil) -> Data? {
        guard valid(rules, blocks: blocks),
              let data = try? SharedConfigurationLocation.encoder.encode(File(schemaVersion: 1, rules: rules.map(Stored.init))),
              data.count <= maximumPayloadBytes else { return nil }
        return data
    }

    static func decode(_ data: Data, blocks: [UnicodeBlock]? = nil) -> [FontRule]? {
        guard data.count <= maximumPayloadBytes, let file = try? JSONDecoder().decode(File.self, from: data), file.schemaVersion == 1 else { return nil }
        let rules = file.rules.compactMap(\.rule)
        guard rules.count == file.rules.count, valid(rules, blocks: blocks) else { return nil }
        return rules
    }

    static func valid(_ rules: [FontRule], blocks: [UnicodeBlock]?) -> Bool {
        let table = blocks ?? rules.compactMap { rule -> UnicodeBlock? in
            guard case let .block(block) = rule.selector else { return nil }
            return UnicodeBlock(name: block.name, start: block.first, end: block.last)
        }
        return rules.allSatisfy { $0.selector.isWellFormed && validID($0.id) } && Set(rules.map(\.id)).count == rules.count
            && FontRuleValidator.validate(rules, blocks: table).isEmpty
    }

    private static func validID(_ id: String) -> Bool {
        (1...128).contains(id.utf8.count) && !id.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}

/// The keyboard's reader. It checks the file's identity (path, inode, size
/// and modification time) on appear or refresh and decodes the JSON only
/// when that changed: never per keystroke, never TOML.
final class FontRuleSnapshotReader {
    private let store: FontRuleStore
    private var stamp: [String]?
    private(set) var rules: [FontRule] = []
    /// How often the JSON was actually decoded; a diagnostic for tests.
    private(set) var decodeCount = 0

    init(store: FontRuleStore = .shared) { self.store = store }

    /// True when the rules changed. An unusable file reads as no rules.
    @discardableResult func refresh() -> Bool {
        let url = store.directory()?.appendingPathComponent(FontRuleStore.filename)
        let attributes = url.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) } ?? [:]
        let next = [url?.path ?? "", "\(attributes[.systemFileNumber] ?? "")", "\(attributes[.size] ?? "")",
                    "\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"]
        guard next != stamp else { return false }
        stamp = next
        decodeCount += 1
        let loaded = store.load() ?? []
        guard loaded != rules else { return false }
        rules = loaded
        return true
    }
}
