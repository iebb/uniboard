import Foundation

/// A bounded, deterministic modern Hangul composer for ASCII two-set key IDs.
///
/// This is not a romanization parser or a host-text IME. Uppercase IDs represent
/// Shift, not capitalization. Unsupported input throws; it is never dropped,
/// normalized, transliterated, or passed through. Callers retain literal input.
/// Incomplete syllables use compatibility jamo; complete syllables use one NFC
/// Hangul scalar. No implicit ㅇ, repeated-key tense consonants, archaic jamo,
/// or nonstandard incremental vowel combinations are inferred.
struct KoreanHangulComposer: Sendable {
    static let maximumRawInputScalars = 256

    enum InputError: Error, Equatable {
        case inputTooLong
        /// Zero-based Unicode scalar offset in the supplied whole buffer.
        case unsupportedKey(index: Int, scalar: UInt32)
    }

    /// Declarative key data only. A downloaded, separately authenticated data
    /// pack can construct this table after decoding; no code/rules are loaded.
    /// Validation bounds the table to all 52 ASCII letter IDs, exactly once,
    /// each producing one modern compatibility onset consonant or vowel.
    /// It validates structure, not provenance or fidelity to a named layout.
    struct KeyMapping: Sendable {
        struct Entry: Codable, Equatable, Sendable {
            let key: String
            let jamo: String
        }

        enum ValidationError: Error, Equatable {
            case dataTooLarge
            case invalidJSON
            case unsupportedSchemaVersion
            case incorrectEntryCount
            case invalidKey(entry: Int)
            case duplicateKey(String)
            case invalidJamo(entry: Int)
        }

        static let maximumJSONBytes = 16_384
        private let tokens: [UInt32: Token]

        /// Bounded data-only schema: {"schemaVersion":1,"entries":[
        /// {"key":"r","jamo":"ㄱ"}, ... all 52 IDs ...]}.
        /// Pack integrity/provenance and transport remain the caller's job.
        /// Only these fields affect behavior; no downloaded composition rules.
        init(jsonData: Data) throws {
            guard jsonData.count <= Self.maximumJSONBytes else {
                throw ValidationError.dataTooLarge
            }
            let document: Document
            do {
                document = try JSONDecoder().decode(Document.self, from: jsonData)
            } catch {
                throw ValidationError.invalidJSON
            }
            guard document.schemaVersion == 1 else {
                throw ValidationError.unsupportedSchemaVersion
            }
            try self.init(entries: document.entries)
        }

        private struct Document: Decodable {
            let schemaVersion: Int
            let entries: [Entry]
        }

        init(entries: [Entry]) throws {
            guard entries.count == 52 else { throw ValidationError.incorrectEntryCount }
            var tokens: [UInt32: Token] = [:]
            for (index, entry) in entries.enumerated() {
                // Bounded scalar iteration, including for hostile large strings.
                var keys = entry.key.unicodeScalars.makeIterator()
                guard let key = keys.next(), keys.next() == nil,
                      Self.isASCIIKey(key.value) else {
                    throw ValidationError.invalidKey(entry: index)
                }
                guard tokens[key.value] == nil else {
                    throw ValidationError.duplicateKey(entry.key)
                }
                var jamo = entry.jamo.unicodeScalars.makeIterator()
                guard let scalar = jamo.next(), jamo.next() == nil,
                      let token = Token(compatibilityScalar: scalar.value) else {
                    throw ValidationError.invalidJamo(entry: index)
                }
                tokens[key.value] = token
            }
            self.tokens = tokens
        }

        fileprivate func token(for scalar: UInt32) -> Token? { tokens[scalar] }

        private static func isASCIIKey(_ value: UInt32) -> Bool {
            (65...90).contains(value) || (97...122).contains(value)
        }
    }

    let mapping: KeyMapping
    private(set) var rawInput = ""
    private(set) var output = ""

    /// No built-in key map: production must supply validated mapping data.
    init(mapping: KeyMapping) {
        self.mapping = mapping
    }

    /// Pure whole-buffer conversion. At most 257 input scalars are inspected.
    func compose(_ rawInput: String) throws -> String {
        let tokens = try validatedTokens(rawInput)
        var state = Composition()
        for token in tokens { state.accept(token) }
        state.flush()
        return state.output
    }

    /// Atomic replacement: invalid input leaves rawInput and output unchanged.
    mutating func replaceRawInput(_ keys: String) throws {
        let composed = try compose(keys)
        rawInput = keys
        output = composed
    }

    /// Atomic append of zero or more keys, preserving exact case and order.
    mutating func append(_ keys: String) throws {
        // Validate before concatenating, so an unbounded argument is not copied.
        _ = try validatedTokens(keys, offset: rawInput.utf8.count)
        try replaceRawInput(rawInput + keys)
    }

    /// Undo exactly one raw ASCII key, not one rendered syllable/jamo. Reparse
    /// deliberately restores ambiguous compound/syllable boundaries correctly.
    /// Returns false only when the buffer was already empty. Never edits a host.
    @discardableResult
    mutating func backspace() -> Bool {
        guard !rawInput.isEmpty else { return false }
        rawInput.removeLast()
        // Invariant: only successfully validated ASCII enters this buffer.
        output = try! compose(rawInput)
        return true
    }

    private func validatedTokens(_ keys: String, offset: Int = 0) throws -> [Token] {
        var result: [Token] = []
        for scalar in keys.unicodeScalars {
            let index = offset + result.count
            guard index < Self.maximumRawInputScalars else { throw InputError.inputTooLong }
            guard let token = mapping.token(for: scalar.value) else {
                throw InputError.unsupportedKey(index: index, scalar: scalar.value)
            }
            result.append(token)
        }
        return result
    }

    fileprivate enum Token: Sendable {
        case consonant(leading: Int, trailing: Int?)
        case vowel(Int)

        init?(compatibilityScalar: UInt32) {
            if let leading = KoreanHangulComposer.leadingScalars.firstIndex(of: compatibilityScalar) {
                self = .consonant(leading: leading,
                                  trailing: KoreanHangulComposer.trailingScalars.firstIndex(of: compatibilityScalar))
            } else if (0x314F...0x3163).contains(compatibilityScalar) {
                self = .vowel(Int(compatibilityScalar - 0x314F))
            } else {
                return nil
            }
        }
    }

    private struct Composition {
        var output = ""
        var leading: Int?
        var vowel: Int?
        var trailing = 0

        mutating func accept(_ token: Token) {
            switch token {
            case .consonant(let nextLeading, let nextTrailing):
                if leading != nil, vowel != nil, let nextTrailing {
                    if trailing == 0 {
                        trailing = nextTrailing
                        return
                    }
                    if let compound = KoreanHangulComposer.compoundFinal(trailing, nextTrailing) {
                        trailing = compound
                        return
                    }
                }
                flush()
                leading = nextLeading

            case .vowel(let nextVowel):
                guard let currentVowel = vowel else {
                    vowel = nextVowel
                    return
                }
                if trailing != 0 {
                    // A compound final keeps its first part; its second part
                    // becomes the next onset. A simple/tense final moves whole.
                    let split = KoreanHangulComposer.splitFinal(trailing)
                    let moving = KoreanHangulComposer.trailingScalars[split.moving]
                    trailing = split.remaining
                    flush()
                    leading = KoreanHangulComposer.leadingScalars.firstIndex(of: moving)!
                    vowel = nextVowel
                } else if let compound = KoreanHangulComposer.compoundVowel(currentVowel, nextVowel) {
                    vowel = compound
                } else {
                    flush()
                    vowel = nextVowel
                }
            }
        }

        mutating func flush() {
            if let leading, let vowel {
                // Unicode Standard §3.12, Hangul Syllable Composition:
                // SBase + (LIndex * VCount + VIndex) * TCount + TIndex.
                // https://www.unicode.org/versions/Unicode16.0.0/core-spec/chapter-3/#G24646
                let scalar = 0xAC00 + (leading * 21 + vowel) * 28 + trailing
                output.unicodeScalars.append(Unicode.Scalar(scalar)!)
            } else if let leading {
                output.unicodeScalars.append(Unicode.Scalar(KoreanHangulComposer.leadingScalars[leading])!)
            } else if let vowel {
                output.unicodeScalars.append(Unicode.Scalar(0x314F + vowel)!)
            }
            leading = nil
            vowel = nil
            trailing = 0
        }
    }

    // Unicode's modern L and T ordering. Zero is the absence of a final.
    private static let leadingScalars: [UInt32] = [
        0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141,
        0x3142, 0x3143, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149,
        0x314A, 0x314B, 0x314C, 0x314D, 0x314E
    ]
    private static let trailingScalars: [UInt32] = [
        0, 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136, 0x3137,
        0x3139, 0x313A, 0x313B, 0x313C, 0x313D, 0x313E, 0x313F, 0x3140,
        0x3141, 0x3142, 0x3144, 0x3145, 0x3146, 0x3147, 0x3148, 0x314A,
        0x314B, 0x314C, 0x314D, 0x314E
    ]

    private static func compoundVowel(_ first: Int, _ second: Int) -> Int? {
        switch (first, second) {
        case (8, 0): return 9    // ㅗ + ㅏ = ㅘ
        case (8, 1): return 10   // ㅗ + ㅐ = ㅙ
        case (8, 20): return 11  // ㅗ + ㅣ = ㅚ
        case (13, 4): return 14  // ㅜ + ㅓ = ㅝ
        case (13, 5): return 15  // ㅜ + ㅔ = ㅞ
        case (13, 20): return 16 // ㅜ + ㅣ = ㅟ
        case (18, 20): return 19 // ㅡ + ㅣ = ㅢ
        default: return nil
        }
    }

    private static func compoundFinal(_ first: Int, _ second: Int) -> Int? {
        switch (first, second) {
        case (1, 19): return 3  // ㄱㅅ
        case (4, 22): return 5  // ㄴㅈ
        case (4, 27): return 6  // ㄴㅎ
        case (8, 1): return 9   // ㄹㄱ
        case (8, 16): return 10 // ㄹㅁ
        case (8, 17): return 11 // ㄹㅂ
        case (8, 19): return 12 // ㄹㅅ
        case (8, 25): return 13 // ㄹㅌ
        case (8, 26): return 14 // ㄹㅍ
        case (8, 27): return 15 // ㄹㅎ
        case (17, 19): return 18 // ㅂㅅ
        default: return nil
        }
    }

    private static func splitFinal(_ final: Int) -> (remaining: Int, moving: Int) {
        switch final {
        case 3: return (1, 19)
        case 5: return (4, 22)
        case 6: return (4, 27)
        case 9: return (8, 1)
        case 10: return (8, 16)
        case 11: return (8, 17)
        case 12: return (8, 19)
        case 13: return (8, 25)
        case 14: return (8, 26)
        case 15: return (8, 27)
        case 18: return (17, 19)
        default: return (0, final)
        }
    }
}
