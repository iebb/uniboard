import Foundation

// A bounded TOML 1.0 reader and deterministic writer for the portable
// configuration file (docs/configuration-format.md). App only: the keyboard
// never parses TOML. Dates and times are rejected rather than kept.

/// A 1-based line and Unicode scalar column. A CRLF is one line break.
struct TOMLPosition: Hashable, Sendable {
    let line: Int
    let column: Int
}

/// Bounds enforced while reading. Exceeding any of them is an error, never truncation.
struct TOMLLimits: Hashable, Sendable {
    var maximumBytes = 4_000_000
    var maximumDepth = 16
    var maximumKeyBytes = 256
    var maximumStringBytes = 65_536
    var maximumArrayElements = 8_192
    var maximumValues = 500_000
    static let standard = TOMLLimits()
}

struct TOMLError: Error, Hashable, Sendable, CustomStringConvertible {
    enum Reason: Hashable, Sendable {
        case tooLarge(limit: Int)
        case invalidUTF8
        case controlCharacter(UInt32)
        case expected(String)
        case unterminatedString
        case invalidEscape
        case invalidEscapedScalar
        case invalidNumber
        case numberOutOfRange
        case dateTimeUnsupported
        case duplicateKey(String)
        case tableRedefined(String)
        case notATable(String)
        case tooDeep(limit: Int)
        case keyTooLong(limit: Int)
        case stringTooLong(limit: Int)
        case arrayTooLong(limit: Int)
        case tooManyValues(limit: Int)
    }
    let reason: Reason
    let position: TOMLPosition

    var message: String {
        switch reason {
        case let .tooLarge(limit): return "The file is larger than \(limit) bytes."
        case .invalidUTF8: return "The text isn’t valid UTF-8."
        case let .controlCharacter(value): return "The control character \(String(format: "U+%04X", value)) must be escaped."
        case let .expected(what): return "Expected \(what)."
        case .unterminatedString: return "This string has no closing quote."
        case .invalidEscape: return "This escape sequence isn’t valid."
        case .invalidEscapedScalar: return "This escape doesn’t name a Unicode scalar value."
        case .invalidNumber: return "This number isn’t valid."
        case .numberOutOfRange: return "This number is too large."
        case .dateTimeUnsupported: return "Dates and times aren’t used in Uniboard configurations."
        case let .duplicateKey(key): return "\(key) appears more than once."
        case let .tableRedefined(key): return "The table \(key) is defined more than once."
        case let .notATable(key): return "\(key) is already defined and can’t be extended."
        case let .tooDeep(limit): return "Tables and arrays are nested more than \(limit) levels deep."
        case let .keyTooLong(limit): return "This key is longer than \(limit) bytes."
        case let .stringTooLong(limit): return "This string is longer than \(limit) bytes."
        case let .arrayTooLong(limit): return "This array has more than \(limit) elements."
        case let .tooManyValues(limit): return "The file has more than \(limit) values."
        }
    }
    var description: String { "Check line \(position.line), column \(position.column): \(message)" }
}

/// A parsed value. Strings compare by exact Unicode scalars, never by
/// canonical equivalence; tables compare without regard to key order.
enum TOMLValue: Sendable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case array([TOMLValue])
    case table(TOMLTable)

    var stringValue: String? { if case let .string(value) = self { return value } else { return nil } }
    var integerValue: Int64? { if case let .integer(value) = self { return value } else { return nil } }
    var floatValue: Double? { if case let .float(value) = self { return value } else { return nil } }
    var booleanValue: Bool? { if case let .boolean(value) = self { return value } else { return nil } }
    var arrayValue: [TOMLValue]? { if case let .array(value) = self { return value } else { return nil } }
    var tableValue: TOMLTable? { if case let .table(value) = self { return value } else { return nil } }
}

extension TOMLValue: Equatable {
    static func == (lhs: TOMLValue, rhs: TOMLValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)): return a.unicodeScalars.elementsEqual(b.unicodeScalars)
        case let (.integer(a), .integer(b)): return a == b
        case let (.float(a), .float(b)): return a.isNaN && b.isNaN || a.bitPattern == b.bitPattern
        case let (.boolean(a), .boolean(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.table(a), .table(b)): return a == b
        default: return false
        }
    }
}

/// Keys hashed and compared by exact scalar sequence.
private struct TOMLKey: Hashable {
    let text: String
    init(_ text: String) { self.text = text }
    static func == (lhs: TOMLKey, rhs: TOMLKey) -> Bool { lhs.text.unicodeScalars.elementsEqual(rhs.text.unicodeScalars) }
    func hash(into hasher: inout Hasher) { for scalar in text.unicodeScalars { hasher.combine(scalar.value) } }
}

/// An insertion-ordered table. Parsing records where each key was defined.
struct TOMLTable: Sendable, Equatable {
    private(set) var keys: [String] = []
    private var storage: [TOMLKey: TOMLValue] = [:]
    private var positions: [TOMLKey: TOMLPosition] = [:]

    init() {}
    init(_ entries: KeyValuePairs<String, TOMLValue>) {
        for (key, value) in entries { self[key] = value }
    }

    var count: Int { keys.count }
    var isEmpty: Bool { keys.isEmpty }
    var entries: [(key: String, value: TOMLValue)] { keys.map { ($0, storage[TOMLKey($0)]!) } }

    /// Setting a new key appends it; replacing keeps its place; nil removes it.
    subscript(key: String) -> TOMLValue? {
        get { storage[TOMLKey(key)] }
        set {
            let tomlKey = TOMLKey(key)
            if let newValue {
                if storage.updateValue(newValue, forKey: tomlKey) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: tomlKey) != nil {
                keys.removeAll { TOMLKey($0) == tomlKey }
                positions[tomlKey] = nil
            }
        }
    }

    /// Where the parsed file defined `key`, if it came from a file.
    func position(of key: String) -> TOMLPosition? { positions[TOMLKey(key)] }

    fileprivate mutating func append(_ key: String, _ value: TOMLValue, at position: TOMLPosition) {
        self[key] = value
        positions[TOMLKey(key)] = position
    }

    static func == (lhs: TOMLTable, rhs: TOMLTable) -> Bool {
        lhs.count == rhs.count && lhs.storage.allSatisfy { rhs.storage[$0.key] == $0.value }
    }
}

enum TOMLDocument {
    /// Parses a whole UTF-8 file. Throws `TOMLError` with a line and column.
    static func parse(_ data: Data, limits: TOMLLimits = .standard) throws -> TOMLTable {
        guard data.count <= limits.maximumBytes else {
            throw TOMLError(reason: .tooLarge(limit: limits.maximumBytes), position: TOMLPosition(line: 1, column: 1))
        }
        return try TOMLParser(data: data, limits: limits).parseDocument()
    }

    static func parse(_ text: String, limits: TOMLLimits = .standard) throws -> TOMLTable {
        try parse(Data(text.utf8), limits: limits)
    }

    /// Deterministic: the same table always gives the same text.
    static func write(_ table: TOMLTable) -> String {
        var output = ""
        TOMLWriter.writeBody(table, path: [], into: &output)
        return output
    }
}

// MARK: - Reading

/// A-Z, a-z, 0-9, "-" and "_": the characters of a bare key.
private func isBareKeyScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F: return true
    default: return false
    }
}

private final class TOMLParseTable {
    enum State { case implicit, explicit, dotted }
    var state: State
    var keys: [String] = []
    var entries: [TOMLKey: TOMLParseEntry] = [:]
    var positions: [TOMLKey: TOMLPosition] = [:]

    init(_ state: State) { self.state = state }

    func add(_ key: String, _ entry: TOMLParseEntry, at position: TOMLPosition) {
        keys.append(key)
        entries[TOMLKey(key)] = entry
        positions[TOMLKey(key)] = position
    }

    func value() -> TOMLTable {
        var table = TOMLTable()
        for key in keys {
            let tomlKey = TOMLKey(key)
            switch entries[tomlKey]! {
            case let .value(value): table.append(key, value, at: positions[tomlKey]!)
            case let .table(child): table.append(key, .table(child.value()), at: positions[tomlKey]!)
            case let .tables(list): table.append(key, .array(list.tables.map { .table($0.value()) }), at: positions[tomlKey]!)
            }
        }
        return table
    }
}

private final class TOMLParseList {
    var tables: [TOMLParseTable]
    init(_ tables: [TOMLParseTable]) { self.tables = tables }
}

private enum TOMLParseEntry {
    case value(TOMLValue)
    case table(TOMLParseTable)
    case tables(TOMLParseList)
}

private final class TOMLParser {
    private typealias KeyPart = (name: String, index: Int)
    private let text: [Unicode.Scalar]
    private let lineStarts: [Int]
    private let limits: TOMLLimits
    private let root = TOMLParseTable(.explicit)
    private var index = 0
    private var valueCount = 0

    init(data: Data, limits: TOMLLimits) throws {
        self.limits = limits
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(data.count)
        var lineStarts = [0]
        var line = 1
        var column = 1
        var decoder = Unicode.UTF8()
        var bytes = data.makeIterator()
        var skippedMark = false
        decoding: while true {
            switch decoder.decode(&bytes) {
            case let .scalarValue(scalar):
                // A leading byte order mark isn't content.
                if scalar == "\u{FEFF}" && scalars.isEmpty && !skippedMark { skippedMark = true; continue }
                scalars.append(scalar)
                column += 1
                if scalar == "\n" { line += 1; column = 1; lineStarts.append(scalars.count) }
            case .emptyInput: break decoding
            case .error: throw TOMLError(reason: .invalidUTF8, position: TOMLPosition(line: line, column: column))
            }
        }
        text = scalars
        self.lineStarts = lineStarts
    }

    // MARK: Positions and errors

    private func position(_ offset: Int) -> TOMLPosition {
        var low = 0
        var high = lineStarts.count
        while low + 1 < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle }
        }
        return TOMLPosition(line: low + 1, column: offset - lineStarts[low] + 1)
    }

    private func error(_ reason: TOMLError.Reason, at offset: Int? = nil) -> TOMLError {
        TOMLError(reason: reason, position: position(offset ?? index))
    }

    private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        index + offset < text.count ? text[index + offset] : nil
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 && scalar != "\t" || scalar.value == 0x7F
    }

    private static func isDigit(_ scalar: Unicode.Scalar?) -> Bool {
        scalar.map { $0.value >= 0x30 && $0.value <= 0x39 } ?? false
    }

    private static func hexValue(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar.value {
        case 0x30...0x39: return scalar.value - 0x30
        case 0x41...0x46: return scalar.value - 0x37
        case 0x61...0x66: return scalar.value - 0x57
        default: return nil
        }
    }

    private static func keyPath(_ names: [String]) -> String {
        names.map(TOMLWriter.key).joined(separator: ".")
    }

    // MARK: Layout

    private func skipWhitespace() {
        while let scalar = peek(), scalar == " " || scalar == "\t" { index += 1 }
    }

    /// At a newline: its length (1 for LF, 2 for CRLF), else nil.
    private func newlineLength(at offset: Int) -> Int? {
        guard offset < text.count else { return nil }
        if text[offset] == "\n" { return 1 }
        return text[offset] == "\r" && offset + 1 < text.count && text[offset + 1] == "\n" ? 2 : nil
    }

    private func skipComment() throws {
        index += 1
        while let scalar = peek(), newlineLength(at: index) == nil {
            if Self.isControl(scalar) { throw error(.controlCharacter(scalar.value)) }
            index += 1
        }
    }

    /// Whitespace, newlines and comments between array elements.
    private func skipBlank() throws {
        while let scalar = peek() {
            if scalar == " " || scalar == "\t" { index += 1 }
            else if let length = newlineLength(at: index) { index += length }
            else if scalar == "#" { try skipComment() }
            else { return }
        }
    }

    private func expectLineEnd() throws {
        skipWhitespace()
        if peek() == "#" { try skipComment() }
        guard peek() != nil else { return }
        guard let length = newlineLength(at: index) else { throw error(.expected("a new line")) }
        index += length
    }

    // MARK: Document

    func parseDocument() throws -> TOMLTable {
        var current = root
        var depth = 0
        var path: [String] = []
        while true {
            skipWhitespace()
            guard let scalar = peek() else { break }
            if scalar == "[" {
                (current, depth, path) = try parseHeader()
            } else if scalar != "#" && newlineLength(at: index) == nil {
                try parseKeyValue(into: current, depth: depth, path: path)
            }
            try expectLineEnd()
        }
        return root.value()
    }

    private func parseKey() throws -> [KeyPart] {
        var parts: [KeyPart] = []
        repeat {
            if !parts.isEmpty { index += 1 }
            skipWhitespace()
            let start = index
            let name: String
            if peek() == "\"" || peek() == "'" {
                name = try parseString(quote: peek()!, multiline: false)
            } else {
                var bare = String.UnicodeScalarView()
                while let scalar = peek(), isBareKeyScalar(scalar) { bare.append(scalar); index += 1 }
                guard !bare.isEmpty else { throw error(.expected("a key")) }
                name = String(bare)
            }
            guard name.utf8.count <= limits.maximumKeyBytes else { throw error(.keyTooLong(limit: limits.maximumKeyBytes), at: start) }
            parts.append((name, start))
            skipWhitespace()
        } while peek() == "."
        return parts
    }

    private func parseHeader() throws -> (TOMLParseTable, Int, [String]) {
        let start = index
        index += 1
        let isArray = peek() == "["
        if isArray { index += 1 }
        let parts = try parseKey()
        guard peek() == "]" else { throw error(.expected("]")) }
        index += 1
        if isArray {
            guard peek() == "]" else { throw error(.expected("]]")) }
            index += 1
        }
        let names = parts.map { $0.name }
        var table = root
        var depth = 0
        for (offset, part) in parts.dropLast().enumerated() {
            switch table.entries[TOMLKey(part.name)] {
            case nil:
                let child = TOMLParseTable(.implicit)
                table.add(part.name, .table(child), at: position(part.index))
                table = child
                depth += 1
            case let .table(child)?:
                table = child
                depth += 1
            case let .tables(list)?:
                table = list.tables[list.tables.count - 1]
                depth += 2
            case .value?:
                throw error(.notATable(Self.keyPath(Array(names[...offset]))), at: part.index)
            }
        }
        let last = parts[parts.count - 1]
        let key = TOMLKey(last.name)
        let child = TOMLParseTable(.explicit)
        switch (isArray, table.entries[key]) {
        case (true, nil):
            table.add(last.name, .tables(TOMLParseList([child])), at: position(last.index))
            depth += 2
        case let (true, .tables(list)?):
            guard list.tables.count < limits.maximumArrayElements else {
                throw error(.arrayTooLong(limit: limits.maximumArrayElements), at: start)
            }
            list.tables.append(child)
            depth += 2
        case (false, nil):
            table.add(last.name, .table(child), at: position(last.index))
            depth += 1
        case let (false, .table(existing)?) where existing.state == .implicit:
            existing.state = .explicit
            return try checkedHeader(existing, depth: depth + 1, path: names, start: start)
        default:
            throw error(.tableRedefined(Self.keyPath(names)), at: last.index)
        }
        return try checkedHeader(child, depth: depth, path: names, start: start)
    }

    private func checkedHeader(_ table: TOMLParseTable, depth: Int, path: [String], start: Int) throws -> (TOMLParseTable, Int, [String]) {
        guard depth <= limits.maximumDepth else { throw error(.tooDeep(limit: limits.maximumDepth), at: start) }
        return (table, depth, path)
    }

    private func parseKeyValue(into table: TOMLParseTable, depth: Int, path: [String]) throws {
        let parts = try parseKey()
        guard peek() == "=" else { throw error(.expected("=")) }
        index += 1
        skipWhitespace()
        let value = try parseValue(depth: depth + parts.count - 1)
        var target = table
        for (offset, part) in parts.dropLast().enumerated() {
            switch target.entries[TOMLKey(part.name)] {
            case nil:
                let child = TOMLParseTable(.dotted)
                target.add(part.name, .table(child), at: position(part.index))
                target = child
            case let .table(child)? where child.state == .dotted:
                target = child
            default:
                throw error(.notATable(Self.keyPath(path + parts[...offset].map { $0.name })), at: part.index)
            }
        }
        let last = parts[parts.count - 1]
        guard target.entries[TOMLKey(last.name)] == nil else {
            throw error(.duplicateKey(Self.keyPath(path + parts.map { $0.name })), at: last.index)
        }
        target.add(last.name, .value(value), at: position(last.index))
    }

    // MARK: Values

    private func parseValue(depth: Int) throws -> TOMLValue {
        guard depth <= limits.maximumDepth else { throw error(.tooDeep(limit: limits.maximumDepth)) }
        valueCount += 1
        guard valueCount <= limits.maximumValues else { throw error(.tooManyValues(limit: limits.maximumValues)) }
        guard let scalar = peek() else { throw error(.expected("a value")) }
        switch scalar {
        case "\"", "'": return .string(try parseString(quote: scalar, multiline: peek(1) == scalar && peek(2) == scalar))
        case "[": return try parseArray(depth: depth)
        case "{": return try parseInlineTable(depth: depth)
        default: return try parseToken()
        }
    }

    /// Basic strings (`"`) take escapes; literal strings (`'`) don't.
    private func parseString(quote: Unicode.Scalar, multiline: Bool) throws -> String {
        let start = index
        let escapes = quote == "\""
        var output = String.UnicodeScalarView()
        index += multiline ? 3 : 1
        if multiline, let length = newlineLength(at: index) { index += length }
        while true {
            guard let scalar = peek() else { throw error(.unterminatedString, at: start) }
            if scalar == quote {
                guard multiline else { index += 1; break }
                var run = 0
                while peek(run) == quote { run += 1 }
                if run >= 3 {
                    // Up to two quotes may sit just before the closing delimiter.
                    let closing = min(run, 5)
                    output.append(contentsOf: repeatElement(quote, count: closing - 3))
                    index += closing
                    break
                }
                output.append(contentsOf: repeatElement(quote, count: run))
                index += run
            } else if scalar == "\\" && escapes {
                if multiline, let next = lineEndingBackslash() { index = next } else { output.append(try parseEscape()) }
            } else if multiline, let length = newlineLength(at: index) {
                output.append("\n")
                index += length
            } else if Self.isControl(scalar) {
                throw error(.controlCharacter(scalar.value))
            } else {
                output.append(scalar)
                index += 1
            }
        }
        let result = String(output)
        guard result.utf8.count <= limits.maximumStringBytes else { throw error(.stringTooLong(limit: limits.maximumStringBytes), at: start) }
        return result
    }

    /// A backslash, optional spaces, then a newline: skips to the next non-blank.
    private func lineEndingBackslash() -> Int? {
        var offset = index + 1
        while offset < text.count, text[offset] == " " || text[offset] == "\t" { offset += 1 }
        guard newlineLength(at: offset) != nil else { return nil }
        while offset < text.count {
            if text[offset] == " " || text[offset] == "\t" { offset += 1 }
            else if let length = newlineLength(at: offset) { offset += length }
            else { break }
        }
        return offset
    }

    private func parseEscape() throws -> Unicode.Scalar {
        let start = index
        index += 1
        guard let scalar = peek() else { throw error(.invalidEscape, at: start) }
        index += 1
        switch scalar {
        case "b": return "\u{08}"
        case "t": return "\t"
        case "n": return "\n"
        case "f": return "\u{0C}"
        case "r": return "\r"
        case "\"": return "\""
        case "\\": return "\\"
        case "u", "U":
            let count = scalar == "u" ? 4 : 8
            guard index + count <= text.count else { throw error(.invalidEscape, at: start) }
            var value: UInt32 = 0
            for digit in text[index..<(index + count)] {
                guard let nibble = Self.hexValue(digit) else { throw error(.invalidEscape, at: start) }
                value = value << 4 | nibble
            }
            guard let result = Unicode.Scalar(value) else { throw error(.invalidEscapedScalar, at: start) }
            index += count
            return result
        default:
            throw error(.invalidEscape, at: start)
        }
    }

    private func parseArray(depth: Int) throws -> TOMLValue {
        index += 1
        var items: [TOMLValue] = []
        while true {
            try skipBlank()
            if peek() == "]" { break }
            guard items.count < limits.maximumArrayElements else { throw error(.arrayTooLong(limit: limits.maximumArrayElements)) }
            items.append(try parseValue(depth: depth + 1))
            try skipBlank()
            if peek() == "," { index += 1; continue }
            guard peek() == "]" else { throw error(.expected("a comma or ]")) }
            break
        }
        index += 1
        return .array(items)
    }

    private func parseInlineTable(depth: Int) throws -> TOMLValue {
        index += 1
        let table = TOMLParseTable(.explicit)
        skipWhitespace()
        if peek() != "}" {
            while true {
                try parseKeyValue(into: table, depth: depth + 1, path: [])
                skipWhitespace()
                if peek() == "," { index += 1; continue }
                guard peek() == "}" else { throw error(.expected("a comma or }")) }
                break
            }
        }
        index += 1
        return .table(table.value())
    }

    /// Booleans, numbers and (rejected) dates and times.
    private func parseToken() throws -> TOMLValue {
        let start = index
        if Self.isDigit(peek()) && Self.isDigit(peek(1)) && (peek(2) == ":" || Self.isDigit(peek(2)) && Self.isDigit(peek(3)) && peek(4) == "-") {
            throw error(.dateTimeUnsupported)
        }
        var token = ""
        while let scalar = peek(), isBareKeyScalar(scalar) || scalar == "+" || scalar == "." {
            token.unicodeScalars.append(scalar)
            index += 1
        }
        switch token {
        case "": throw error(.expected("a value"), at: start)
        case "true": return .boolean(true)
        case "false": return .boolean(false)
        case "inf", "+inf": return .float(.infinity)
        case "-inf": return .float(-.infinity)
        case "nan", "+nan", "-nan": return .float(.nan)
        default: return try parseNumber(token, at: start)
        }
    }

    /// Digits in `radix` with single underscores between them, without the underscores.
    private static func digits(_ text: Substring, radix: Int) -> String? {
        var result = ""
        var afterUnderscore = true
        for character in text {
            if character == "_" {
                guard !afterUnderscore else { return nil }
                afterUnderscore = true
            } else {
                guard character.isASCII, let value = character.hexDigitValue, value < radix else { return nil }
                result.append(character)
                afterUnderscore = false
            }
        }
        return afterUnderscore ? nil : result
    }

    private static func decimal(_ text: Substring) -> String? {
        digits(text, radix: 10).flatMap { $0 == "0" || $0.first != "0" ? $0 : nil }
    }

    private func parseNumber(_ token: String, at start: Int) throws -> TOMLValue {
        var body = Substring(token)
        let sign = body.first == "+" || body.first == "-" ? String(body.removeFirst()) : ""
        let invalid = error(.invalidNumber, at: start)
        let outOfRange = error(.numberOutOfRange, at: start)
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where body.hasPrefix(prefix) {
            guard sign.isEmpty, let digits = Self.digits(body.dropFirst(2), radix: radix) else { throw invalid }
            guard let value = Int64(digits, radix: radix) else { throw outOfRange }
            return .integer(value)
        }
        let exponentStart = body.firstIndex { $0 == "e" || $0 == "E" }
        let mantissa = body[..<(exponentStart ?? body.endIndex)].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = Self.decimal(mantissa[0]) else { throw invalid }
        guard exponentStart != nil || mantissa.count == 2 else {
            guard let value = Int64((sign == "-" ? "-" : "") + whole) else { throw outOfRange }
            return .integer(value)
        }
        var normalized = sign + whole
        if mantissa.count == 2 {
            guard let fraction = Self.digits(mantissa[1], radix: 10) else { throw invalid }
            normalized += "." + fraction
        }
        if let exponentStart {
            var exponent = body[body.index(after: exponentStart)...]
            let exponentSign = exponent.first == "+" || exponent.first == "-" ? String(exponent.removeFirst()) : ""
            guard let digits = Self.digits(exponent, radix: 10) else { throw invalid }
            normalized += "e" + exponentSign + digits
        }
        guard let value = Double(normalized), value.isFinite else { throw outOfRange }
        return .float(value)
    }
}

// MARK: - Writing

enum TOMLWriter {
    /// Invisible or confusable scalars written as escapes so they can be seen.
    private static let escapedRanges: [ClosedRange<UInt32>] = [
        0x00...0x1F, 0x7F...0x9F, 0xAD...0xAD, 0x61C...0x61C, 0x180B...0x180F,
        0x200B...0x200F, 0x2028...0x202E, 0x2060...0x2064, 0x2066...0x206F,
        0xFE00...0xFE0F, 0xFEFF...0xFEFF, 0xE0000...0xE007F, 0xE0100...0xE01EF
    ]

    static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\u{08}": output += "\\b"
            case "\t": output += "\\t"
            case "\n": output += "\\n"
            case "\u{0C}": output += "\\f"
            case "\r": output += "\\r"
            default:
                if escapedRanges.contains(where: { $0.contains(scalar.value) }) {
                    output += scalar.value > 0xFFFF ? String(format: "\\U%08X", scalar.value) : String(format: "\\u%04X", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }

    static func key(_ text: String) -> String {
        !text.isEmpty && text.unicodeScalars.allSatisfy(isBareKeyScalar) ? text : quoted(text)
    }

    static func float(_ value: Double) -> String {
        if value.isNaN { return "nan" }
        if value.isInfinite { return value < 0 ? "-inf" : "inf" }
        return "\(value)"
    }

    static func inline(_ value: TOMLValue) -> String {
        switch value {
        case let .string(text): return quoted(text)
        case let .integer(number): return String(number)
        case let .float(number): return float(number)
        case let .boolean(flag): return flag ? "true" : "false"
        case let .array(items):
            let parts = items.map(inline)
            let single = "[" + parts.joined(separator: ", ") + "]"
            return single.count <= 80 ? single : "[\n" + parts.map { "  " + $0 + ",\n" }.joined() + "]"
        case let .table(table):
            return table.isEmpty ? "{}" : "{ " + table.entries.map { key($0.key) + " = " + inline($0.value) }.joined(separator: ", ") + " }"
        }
    }

    /// A non-empty array whose elements are all tables: written as `[[path]]`.
    private static func tableArray(_ value: TOMLValue) -> [TOMLTable]? {
        guard let items = value.arrayValue, !items.isEmpty else { return nil }
        let tables = items.compactMap(\.tableValue)
        return tables.count == items.count ? tables : nil
    }

    private static func isPlain(_ value: TOMLValue) -> Bool { value.tableValue == nil && tableArray(value) == nil }

    /// Plain values first (they must precede any header), then tables in order.
    static func writeBody(_ table: TOMLTable, path: [String], into output: inout String) {
        let entries = table.entries
        for (name, value) in entries where isPlain(value) {
            output += key(name) + " = " + inline(value) + "\n"
        }
        for (name, value) in entries {
            let header = (path + [name]).map(key).joined(separator: ".")
            if let child = value.tableValue {
                // A table holding only tables is implied by their headers.
                if child.isEmpty || child.entries.contains(where: { isPlain($0.value) }) {
                    output += (output.isEmpty ? "" : "\n") + "[" + header + "]\n"
                }
                writeBody(child, path: path + [name], into: &output)
            } else if let tables = tableArray(value) {
                for child in tables {
                    output += (output.isEmpty ? "" : "\n") + "[[" + header + "]]\n"
                    writeBody(child, path: path + [name], into: &output)
                }
            }
        }
    }
}
