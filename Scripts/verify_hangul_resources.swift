import Foundation
import CryptoKit

/// Standalone native smoke harness; compile with the four unmodified Shared
/// source files, not as an app target. Argument: generated resource directory.
@main
struct VerifyHangulResources {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verifyPayload(_ directory: URL, source: URL,
                              descriptor: LanguagePackDescriptor) throws {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: directory.path)
        try require(Set(names) == Set(descriptor.files.map(\.path)), "unexpected extracted inventory")
        var total: Int64 = 0
        for file in descriptor.files {
            let url = directory.appendingPathComponent(file.path)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            try require(attributes[.type] as? FileAttributeType == .typeRegular, "not regular: \(file.path)")
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
            try require(permissions >= 0 && permissions & 0o111 == 0, "executable payload: \(file.path)")
            let data = try Data(contentsOf: url)
            try require(Int64(data.count) == file.byteCount, "size mismatch: \(file.path)")
            try require(digest(data) == file.sha256, "hash mismatch: \(file.path)")
            let original = try Data(contentsOf: source.appendingPathComponent(file.path))
            try require(data == original, "extracted bytes differ from original: \(file.path)")
            total += Int64(data.count)
            print("PASS payload \(file.path): \(data.count) bytes SHA256 \(digest(data))")
        }
        try require(total == descriptor.installedBytes, "installed total mismatch")
    }

    static func verifyMapping(at directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("mapping.json"))
        let mapping = try KoreanHangulComposer.KeyMapping(jsonData: data)
        var composer = KoreanHangulComposer(mapping: mapping)
        let examples = [
            ("gksrnr", "한국"), ("rk", "가"), ("Rk", "까"), ("rhk", "과"),
            ("rkqt", "값"), ("rkqtk", "갑사"), ("rkrk", "가가"),
            ("rksk", "가나"), ("gksrmf", "한글"), ("rO", "걔"),
            ("rP", "계"), ("rkTk", "가싸"), ("r", "ㄱ"), ("hk", "ㅘ"), ("", "")
        ]
        for (raw, expected) in examples {
            let actual = try composer.compose(raw)
            try require(Array(actual.unicodeScalars) == Array(expected.unicodeScalars),
                        "compose \(raw): \(actual) != \(expected)")
            print("PASS compose \(raw.debugDescription) -> \(actual.debugDescription)")
        }
        let keys = Array("abcdefghijklmnopqrstuvwxyz")
        let expected = Array("ㅁㅠㅊㅇㄷㄹㅎㅗㅑㅓㅏㅣㅡㅜㅐㅔㅂㄱㄴㅅㅕㅍㅈㅌㅛㅋ")
        let shift = ["r": "ㄲ", "e": "ㄸ", "q": "ㅃ", "t": "ㅆ", "w": "ㅉ", "o": "ㅒ", "p": "ㅖ"]
        for (index, key) in keys.enumerated() {
            let lower = String(key)
            let lowerOutput = try composer.compose(lower)
            let upperOutput = try composer.compose(lower.uppercased())
            try require(lowerOutput == String(expected[index]), "lowercase key mismatch: \(key)")
            try require(upperOutput == (shift[lower] ?? String(expected[index])), "shift key mismatch: \(key)")
        }
        print("PASS all 52 extracted mapping entries and seven Shift forms")
        try composer.append("rkqtk")
        for expected in ["값", "갑", "가", "ㄱ", ""] {
            try require(composer.backspace(), "backspace unexpectedly empty")
            try require(composer.output == expected, "backspace output mismatch")
        }
        try require(!composer.backspace(), "empty backspace unexpectedly succeeded")
        print("PASS extracted mapping keywise backspace 갑사 -> 값 -> 갑 -> 가 -> ㄱ -> empty")
        do {
            _ = try KoreanHangulComposer.KeyMapping(jsonData: Data(repeating: 32, count: 16_385))
            throw Failure(description: "oversized mapping accepted")
        } catch KoreanHangulComposer.KeyMapping.ValidationError.dataTooLarge {
            print("PASS native mapping decoder rejects oversized input")
        }
    }

    static func main() throws {
        try require(CommandLine.arguments.count == 2, "usage: verify-hangul-resources <resource-directory>")
        let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manifest = try Data(contentsOf: source.appendingPathComponent("descriptor.json"))
        let descriptor = try LanguagePackDescriptor.validated(from: manifest)
        try require(descriptor.packID == "korean-hangul-2set" && descriptor.version == "1"
                    && descriptor.modeID == "koreanTwoSetHangul" && descriptor.engineABI == "uniboard-hangul-1",
                    "wrong resource identity")
        try require(descriptor.archiveByteCount == 2_324
                    && descriptor.archiveSHA256 == "a895f37d5e2f329f505587aa8bd44af5cf7b36d774c092f31faa93f6136f3952",
                    "not the exact final publication archive")
        try require(descriptor.sourceURL.absoluteString == "https://uniboard.ieb.app/data/korean/hangul-2set/1/hangul-2set.tar.gz",
                    "wrong final source URL")
        let archive = source.appendingPathComponent("hangul-2set.tar.gz")
        try LanguagePackStore.verifyArchive(at: archive, descriptor: descriptor)
        print("PASS native descriptor validation and streaming archive SHA256 verification")

        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("uniboard-hangul-smoke-" + UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temporary) }
        let extracted = temporary.appendingPathComponent("extracted")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: false)
        let limits = LanguagePackArchive.Limits(decodedBytes: 16_384, entryCount: 3, individualFileBytes: 16_384)
        try LanguagePackArchive.extract(archive: archive, descriptor: descriptor, into: extracted,
                                        archiveRoot: "hangul-2set-1", limits: limits)
        print("PASS existing native bounded tar.gz extractor: archiveRoot=hangul-2set-1, three entries, decoded limit 16384")
        try verifyPayload(extracted, source: source, descriptor: descriptor)
        try verifyMapping(at: extracted)

        // Also exercise the real store publication and verified lease path, not
        // only a loose extraction directory, without any app/network behavior.
        let store = LanguagePackStore(root: temporary.appendingPathComponent("store"))
        let installed = try store.install(manifestData: manifest, expectedRevision: nil) { stage in
            try LanguagePackArchive.extract(archive: archive, descriptor: descriptor, into: stage,
                                            archiveRoot: "hangul-2set-1", limits: limits)
        }
        guard case .available(let lease) = store.resolve(modeID: descriptor.modeID, engineABI: descriptor.engineABI) else {
            throw Failure(description: "installed resource did not resolve to a verified lease")
        }
        defer { lease.release() }
        try require(lease.pack.revision == installed.revision, "lease revision mismatch")
        try verifyPayload(lease.pack.path, source: source, descriptor: descriptor)
        try verifyMapping(at: lease.pack.path)
        print("PASS real store install, full payload verification, publication, resolve and held read lease")

        var damaged = try Data(contentsOf: archive)
        damaged[damaged.count - 1] ^= 1
        let damagedURL = temporary.appendingPathComponent("damaged.tar.gz")
        try damaged.write(to: damagedURL)
        do {
            try LanguagePackStore.verifyArchive(at: damagedURL, descriptor: descriptor)
            throw Failure(description: "tampered archive accepted")
        } catch is LanguagePackError {
            print("PASS native archive verifier rejects same-size byte corruption")
        }
        print("SUCCESS exact final tar.gz native extraction, data decoding, composition, and installed-resource smoke")
    }
}
