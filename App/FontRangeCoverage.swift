#if canImport(UIKit)
import Foundation
import CoreText

/// Counts how many code points of a range or block a named face itself maps
/// to a glyph (its cmap), never a fallback font, and finds the representative
/// characters it draws for tiles and the picker sample. Runs off the main thread,
/// checks for cancellation as it goes, and remembers results until the font
/// library changes. A glyph count is not proof of correct shaping.
actor FontRangeCoverage {
    static let shared = FontRangeCoverage()
    private var cache: [String: Int] = [:]
    private static let cacheLimit = 512

    /// Supported valid scalars in `first...last`, or nil when the face can't be loaded.
    func supportedCount(of face: FontFaceReference, first: UInt32, last: UInt32, loader: FontRuleFaceLoader) async throws -> Int? {
        let key = "\(face.identityKey)|\(face.postScriptName)|\(first)-\(last)|\(loader.revision)"
        if let cached = cache[key] { return cached }
        try Task.checkCancellation()
        guard case let .success(loaded) = loader.load(face) else { return nil }
        let count = try await Self.count(CTFontCopyCharacterSet(loaded.reference), first: first, last: min(last, FontRuleScalar.maximum))
        if cache.count >= Self.cacheLimit { cache.removeAll() }
        cache[key] = count
        return count
    }

    private var samples: [String: [UInt32]?] = [:]

    /// The first `limit` representative characters of `first...last` (in
    /// `catalog`'s edition) that the face itself maps, letters first (see
    /// `FontRuleSample.representative`); nil when the face can't be loaded.
    /// Cached per face, range and limit.
    func drawnSamples(of face: FontFaceReference, first: UInt32, last: UInt32, limit: Int,
                      catalog: UnicodeCatalog, loader: FontRuleFaceLoader) async throws -> [UInt32]? {
        let key = FontRuleSample.cacheKey(face: face, first: first, last: last, limit: limit,
                                          edition: catalog.edition.rawValue + " " + catalog.version, revision: loader.revision)
        if let cached = samples[key] { return cached }
        try Task.checkCancellation()
        let result: [UInt32]?
        if case let .success(loaded) = loader.load(face) {
            let set = CTFontCopyCharacterSet(loaded.reference)
            let rows = catalog.chartRows(in: UnicodeBlock(name: "", start: first, end: min(last, FontRuleScalar.maximum)), columns: 32)
            result = try await FontRuleSample.representative(rows: rows, columns: 32, limit: limit, category: { value in
                guard CFCharacterSetIsLongCharacterMember(set, value), let character = catalog.character(at: value),
                      FontRuleSample.showsGlyph(character) else { return nil }
                return character.category
            }) {
                try Task.checkCancellation()
                await Task.yield()
            }
        } else {
            result = nil
        }
        if samples.count >= Self.cacheLimit { samples.removeAll() }
        samples[key] = .some(result)
        return result
    }

    static func count(_ set: CFCharacterSet, first: UInt32, last: UInt32) async throws -> Int {
        var count = 0
        var value = first
        var sinceCheck = 0
        while value <= last {
            if FontRuleScalar.surrogates.contains(value) {
                value = FontRuleScalar.surrogates.upperBound + 1
                continue
            }
            if CFCharacterSetIsLongCharacterMember(set, value) { count += 1 }
            sinceCheck += 1
            if sinceCheck == 8192 {
                sinceCheck = 0
                try Task.checkCancellation()
                await Task.yield()
            }
            value += 1
        }
        return count
    }
}
#endif
