import Foundation

/// The Under-ConScript Unicode Registry (https://www.kreativekorp.com/ucsur/)
/// assigns Private Use code points to constructed scripts. Its blocks, names
/// and properties come from the bundled UCSUR.txt, which
/// Scripts/build_ucsur.py builds, and show only while ConScript is on.
enum UCSUR {
    struct Block: Equatable, Sendable {
        let start: UInt32
        let end: UInt32
        let name: String
    }

    /// One registry character with its UnicodeData and NamesList fields.
    struct Entry: Equatable, Sendable {
        let codePoint: UInt32
        let name: String
        let category: String
        let combiningClass: Int
        let bidirectionalClass: String?
        let decomposition: String?
        let numericType: String?
        let numericValue: String?
        let uppercase: UInt32?
        let lowercase: UInt32?
        let titlecase: UInt32?
        let section: String?
        let aliases: [String]
    }

    /// Blocks and characters, each in ascending code point order.
    struct Registry: Sendable {
        var blocks: [Block] = []
        var entries: [Entry] = []

        func block(containing codePoint: UInt32) -> Block? {
            var low = 0, high = blocks.count
            while low < high {
                let mid = (low + high) / 2
                if blocks[mid].end < codePoint { low = mid + 1 } else { high = mid }
            }
            return low < blocks.count && blocks[low].start <= codePoint ? blocks[low] : nil
        }

        func entry(at codePoint: UInt32) -> Entry? {
            var low = 0, high = entries.count
            while low < high {
                let mid = (low + high) / 2
                if entries[mid].codePoint < codePoint { low = mid + 1 } else { high = mid }
            }
            return low < entries.count && entries[low].codePoint == codePoint ? entries[low] : nil
        }
    }

    static let registry: Registry = {
        #if SWIFT_PACKAGE
        let bundles = [Bundle.module, Bundle.main]
        #else
        let bundles = [Bundle.main]
        #endif
        // A missing resource reads as an empty registry.
        let text = bundles.lazy.compactMap { $0.url(forResource: "UCSUR", withExtension: "txt") }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }.prefix(1)
        return parse(text.joined())
    }()

    static func block(containing codePoint: UInt32) -> Block? { registry.block(containing: codePoint) }
    static func entry(at codePoint: UInt32) -> Entry? { registry.entry(at: codePoint) }

    /// The three Private Use areas, without their noncharacters.
    static func isPrivateUse(_ codePoint: UInt32) -> Bool {
        (0xE000...0xF8FF).contains(codePoint) || (0xF0000...0xFFFFD).contains(codePoint)
            || (0x100000...0x10FFFD).contains(codePoint)
    }

    /// Lines are `@start\tend\tname` for blocks, or thirteen tab-separated
    /// character fields. Comments, malformed or out-of-order lines and
    /// anything outside Private Use are skipped.
    static func parse(_ text: String) -> Registry {
        var registry = Registry()
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if line.hasPrefix("@") {
                if fields.count == 3, let start = UInt32(fields[0].dropFirst(), radix: 16), let end = UInt32(fields[1], radix: 16),
                   start <= end, isPrivateUse(start), isPrivateUse(end), !fields[2].isEmpty,
                   registry.blocks.last.map({ $0.end < start }) ?? true {
                    registry.blocks.append(Block(start: start, end: end, name: fields[2]))
                }
            } else if fields.count == 13, let point = UInt32(fields[0], radix: 16), isPrivateUse(point),
                      !fields[1].isEmpty, fields[2].count == 2, let combining = Int(fields[3]),
                      registry.entries.last.map({ $0.codePoint < point }) ?? true {
                registry.entries.append(Entry(
                    codePoint: point, name: fields[1], category: fields[2], combiningClass: combining,
                    bidirectionalClass: optional(fields[4]), decomposition: optional(fields[5]),
                    numericType: optional(fields[6]), numericValue: optional(fields[7]),
                    uppercase: UInt32(fields[8], radix: 16), lowercase: UInt32(fields[9], radix: 16),
                    titlecase: UInt32(fields[10], radix: 16), section: optional(fields[11]),
                    aliases: fields[12].split(separator: "|").map(String.init)))
            }
        }
        return registry
    }

    private static func optional(_ field: String) -> String? { field.isEmpty ? nil : field }

    /// `blocks` with each Private Use area split into the registry's blocks
    /// and the Private Use ranges left between them.
    static func splitting(_ blocks: [UnicodeBlock], with registry: [Block]) -> [UnicodeBlock] {
        blocks.flatMap { block -> [UnicodeBlock] in
            guard block.name.contains("Private Use Area") else { return [block] }
            var pieces: [UnicodeBlock] = []
            var next = block.start
            for inner in registry where inner.start >= block.start && inner.end <= block.end {
                if inner.start > next { pieces.append(UnicodeBlock(name: block.name, start: next, end: inner.start - 1)) }
                pieces.append(UnicodeBlock(name: inner.name, start: inner.start, end: inner.end))
                next = inner.end + 1
            }
            if next <= block.end { pieces.append(UnicodeBlock(name: block.name, start: next, end: block.end)) }
            return pieces
        }
    }
}

extension UCSUR.Entry {
    /// This character as the catalog shows it while ConScript is preferred.
    func character(blockName: String, age: String?, versionSortKey: Int, script: String?) -> UnicodeCharacter {
        UnicodeCharacter(codePoint: codePoint, name: name,
                         detail: "Assigned by the ConScript Unicode Registry, not by Unicode. Appearance depends on the font.",
                         blockName: blockName, category: category, isInvisible: ["Zs", "Zl", "Zp", "Cf"].contains(category),
                         age: age, versionSortKey: versionSortKey, combiningClass: combiningClass,
                         bidirectionalClass: bidirectionalClass, script: script, decomposition: decomposition,
                         nameAliases: aliases.map { UnicodeNameAlias(name: $0, kind: "informal") },
                         namesListSection: section, numericValue: numericValue, numericType: numericType,
                         simpleUppercase: uppercase, simpleLowercase: lowercase, simpleTitlecase: titlecase)
    }
}
