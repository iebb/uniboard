import Foundation
import CoreFoundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// One-way app settings: the containing app writes; the keyboard only loads.
/// No query, typed text, favorites or other keyboard state enters this file.
struct UnicodeEditionSettings {
    struct Snapshot: Equatable {
        var edition: UnicodeEdition
        var useUnicodeFonts = false
        var showsCollapseKey = false
        var showsSymbolBar = true
        var searchBarInsteadOfSymbols = false
        var showsNumberRow = true
        /// Enabled base keyboards in switching order; the first is the default.
        var layouts: [String] = [KeyboardAlphabet.english.id]
        var padLayout: KeyboardPadLayout = .ansiNumbers
        var padSymbolMapping: KeyboardPadSymbolMapping = .standard
    }
    static let groupIdentifier = "group.ad.neko.uniboard"
    static let maximumPayloadBytes = 512
    static let maximumLayouts = 8
    static let filename = "unicode-edition-v1.json"
    static let shared = UnicodeEditionSettings()

    typealias ContainerProvider = () -> URL?
    typealias PrefixReader = (URL, Int) throws -> Data
    typealias AtomicWriter = (Data, URL) throws -> Void

    private let containerURL: ContainerProvider
    private let readPrefix: PrefixReader
    private let writeAtomically: AtomicWriter

    init(containerURL: @escaping ContainerProvider = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)
    }, readPrefix: @escaping PrefixReader = UnicodeEditionSettings.readFilePrefix,
         writeAtomically: @escaping AtomicWriter = UnicodeEditionSettings.writeFileAtomically) {
        self.containerURL = containerURL
        self.readPrefix = readPrefix
        self.writeAtomically = writeAtomically
    }

    /// Safe without Full Access. Missing, unavailable, old or malformed data
    /// chooses the current release; it never consults an independent default.
    func load() -> UnicodeEdition { loadSnapshot().edition }

    func loadSnapshot() -> Snapshot {
        guard let container = containerURL(), container.isFileURL,
              let data = try? readPrefix(container.appendingPathComponent(Self.filename), Self.maximumPayloadBytes + 1),
              !data.isEmpty, data.count <= Self.maximumPayloadBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let schema = dictionary["schemaVersion"] as? NSNumber,
              CFGetTypeID(schema) != CFBooleanGetTypeID(),
              let identifier = dictionary["selectionIdentifier"] as? String else { return Snapshot(edition: .latest) }
        let edition = UnicodeEdition.resolve(selectionIdentifier: identifier)
        if schema == NSNumber(value: 1), Set(dictionary.keys) == ["schemaVersion", "selectionIdentifier"] {
            return Snapshot(edition: edition)
        }
        guard let fonts = Self.strictBoolean(dictionary["useUnicodeFonts"]),
              let collapse = Self.strictBoolean(dictionary["showsCollapseKey"]) else { return Snapshot(edition: .latest) }
        if schema == NSNumber(value: 2),
           Set(dictionary.keys) == ["schemaVersion", "selectionIdentifier", "useUnicodeFonts", "showsCollapseKey"] {
            return Snapshot(edition: edition, useUnicodeFonts: fonts, showsCollapseKey: collapse)
        }
        let legacyKeys: Set<String> = ["schemaVersion", "selectionIdentifier", "useUnicodeFonts", "showsCollapseKey", "padLayout", "padSymbolMapping"]
        let barKeys = legacyKeys.union(["showsSymbolBar", "searchBarInsteadOfSymbols"])
        let numberRowKeys = barKeys.union(["showsNumberRow"])
        let modernKeys = numberRowKeys.union(["layouts"])
        guard (schema == NSNumber(value: 3) && Set(dictionary.keys) == legacyKeys)
                || (schema == NSNumber(value: 4) && Set(dictionary.keys) == barKeys)
                || (schema == NSNumber(value: 5) && Set(dictionary.keys) == numberRowKeys)
                || (schema == NSNumber(value: 6) && Set(dictionary.keys) == modernKeys),
              let layout = dictionary["padLayout"] as? String, let pad = KeyboardPadLayout(rawValue: layout),
              let mapping = dictionary["padSymbolMapping"] as? String, let symbols = KeyboardPadSymbolMapping(rawValue: mapping) else { return Snapshot(edition: .latest) }
        var value = Snapshot(edition: edition, useUnicodeFonts: fonts, showsCollapseKey: collapse,
            padLayout: pad, padSymbolMapping: symbols)
        if schema.intValue >= 4 {
            guard let bar = Self.strictBoolean(dictionary["showsSymbolBar"]),
                  let search = Self.strictBoolean(dictionary["searchBarInsteadOfSymbols"]) else { return Snapshot(edition: .latest) }
            value.showsSymbolBar = bar; value.searchBarInsteadOfSymbols = search
        }
        if schema.intValue >= 5 {
            guard let numbers = Self.strictBoolean(dictionary["showsNumberRow"]) else { return Snapshot(edition: .latest) }
            value.showsNumberRow = numbers
        }
        if schema.intValue >= 6 {
            guard let ids = dictionary["layouts"] as? [String], let layouts = Self.layouts(ids) else { return Snapshot(edition: .latest) }
            value.layouts = layouts
        }
        return value
    }

    /// Unknown layouts, perhaps from a newer version, are skipped; at least
    /// one known layout must remain.
    static func layouts(_ ids: [String]) -> [String]? {
        guard (1...maximumLayouts).contains(ids.count), Set(ids).count == ids.count else { return nil }
        let known = ids.filter { KeyboardAlphabet.alphabet(id: $0) != nil }
        return known.isEmpty ? nil : known
    }

    /// Only the containing app calls this method. A failure is reported to the
    /// caller rather than pretending an unsynchronized setting was saved.
    @discardableResult
    func save(_ edition: UnicodeEdition) -> Bool {
        var current = loadSnapshot()
        current.edition = edition
        return save(current)
    }
    @discardableResult
    func save(_ snapshot: Snapshot) -> Bool {
        let identifier = snapshot.edition.selectionIdentifier
        guard UnicodeEdition.resolve(selectionIdentifier: identifier) == snapshot.edition,
              Self.layouts(snapshot.layouts) == snapshot.layouts,
              let container = containerURL(), container.isFileURL,
              let data = try? JSONSerialization.data(withJSONObject: [
                "schemaVersion": 6, "selectionIdentifier": identifier, "layouts": snapshot.layouts,
                "useUnicodeFonts": snapshot.useUnicodeFonts, "showsCollapseKey": snapshot.showsCollapseKey,
                "showsSymbolBar": snapshot.showsSymbolBar, "searchBarInsteadOfSymbols": snapshot.searchBarInsteadOfSymbols,
                "showsNumberRow": snapshot.showsNumberRow,
                "padLayout": snapshot.padLayout.rawValue, "padSymbolMapping": snapshot.padSymbolMapping.rawValue
              ], options: [.sortedKeys]), data.count <= Self.maximumPayloadBytes else { return false }
        do {
            try writeAtomically(data, container.appendingPathComponent(Self.filename))
            return true
        } catch { return false }
    }

    private static func strictBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private enum FileError: Error { case unavailable }

    private static func readFilePrefix(_ url: URL, maximumBytes: Int) throws -> Data {
        // Open the fixed child read-only, without following a symbolic link.
        // Nonblocking avoids a malformed FIFO from hanging the input process.
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw FileError.unavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var data = Data()
        while data.count < maximumBytes {
            let chunk = try handle.read(upToCount: maximumBytes - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    private static func writeFileAtomically(_ data: Data, to url: URL) throws {
        // There is one app-owned writer in a private group container. Reject a
        // pre-existing child link instead of writing through it.
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw FileError.unavailable
        }
        try data.write(to: url, options: [.atomic])
    }
}
