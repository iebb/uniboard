#if canImport(UIKit)
import UIKit
import CoreText
import ObjectiveC

/// One loaded rule face and every CoreText object it depends on. Variable
/// font instances can borrow tables from the CGFont and its data, so the
/// whole chain stays alive together; every UIFont made here retains it too,
/// so a font still shown on screen keeps working after the face leaves the
/// loader's small cache.
final class LoadedRuleFont: NSObject {
    /// A 32-point instance for coverage checks.
    let reference: CTFont
    let graphics: CGFont?
    let dataProvider: CGDataProvider?
    let data: CFData?
    /// The variation instance, applied at every size.
    let descriptor: CTFontDescriptor

    init(reference: CTFont, graphics: CGFont?, dataProvider: CGDataProvider?, data: CFData?, descriptor: CTFontDescriptor) {
        self.reference = reference
        self.graphics = graphics
        self.dataProvider = dataProvider
        self.data = data
        self.descriptor = descriptor
    }

    var postScriptName: String { CTFontCopyPostScriptName(reference) as String }

    private static var ownerKey: UInt8 = 0

    /// The face at `size`. The returned font owns this whole chain.
    func font(size: CGFloat) -> UIFont {
        let font = graphics.map { CTFontCreateWithGraphicsFont($0, size, nil, descriptor) }
            ?? CTFontCreateWithFontDescriptor(descriptor, size, nil)
        objc_setAssociatedObject(font, &Self.ownerKey, self, .OBJC_ASSOCIATION_RETAIN)
        return font as UIFont
    }

    /// The chain a font made by `font(size:)` keeps alive.
    static func owner(of font: UIFont) -> LoadedRuleFont? {
        objc_getAssociatedObject(font, &ownerKey) as? LoadedRuleFont
    }
}

/// Finds and opens the face a font rule names, by its portable identity
/// only: a file face by SHA-256, face index and variation instance; an
/// installed face by PostScript name. A filename is never trusted, nothing
/// is registered with the process, system fonts are never enumerated and
/// nothing is fetched.
struct FontRuleFaceLoader {
    enum Unavailable: Error, Hashable, Sendable {
        /// No face with this identity is on the device, or its file can't be read.
        case missingFile
        /// A file was found but it isn't the named face or instance.
        case identityMismatch
    }

    enum Location: Equatable {
        case file(URL, faceIndex: Int)
        case installed(postScriptName: String)
    }

    var library: CustomFontStore = .shared
    var downloads: UnicodeFontDownloadStore = .shared
    var packFonts: [UnicodeFontDownload] = UnicodeFontPackCatalog.bundled.packs.flatMap(\.fonts)
    /// Fonts listed in the bundled `Fonts/manifest.json`, with their files in the app bundle.
    var bundledAssets: [UnicodeFontAsset] = []
    var bundledURL: (String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: nil, subdirectory: "Fonts") }

    /// Changes when a face may have been added or removed.
    var revision: String { library.revision + "|" + downloads.revision }

    /// Where the face is, in order: the font library, downloaded preview
    /// packs, bundled fonts, then a face installed on the device.
    func locate(_ reference: FontFaceReference) -> Location? {
        switch reference.identity {
        case let .file(sha256, faceIndex, _):
            for face in library.localLibrary.faces {
                guard case let .file(path, digest, index, _) = face.locator, digest == sha256, index == faceIndex,
                      let url = library.url(forRelativePath: path) else { continue }
                return .file(url, faceIndex: faceIndex)
            }
            if let pack = packFonts.first(where: { $0.asset.sha256 == sha256 }), let url = downloads.installedURL(for: pack) {
                return .file(url, faceIndex: faceIndex)
            }
            if let asset = bundledAssets.first(where: { $0.sha256 == sha256 }), let url = bundledURL(asset.filename) {
                return .file(url, faceIndex: faceIndex)
            }
            return nil
        case let .process(name, _):
            return .installed(postScriptName: name)
        }
    }

    func load(_ reference: FontFaceReference) -> Result<LoadedRuleFont, Unavailable> {
        guard reference.isValid, let location = locate(reference) else { return .failure(.missingFile) }
        return load(reference, at: location)
    }

    func load(_ reference: FontFaceReference, at location: Location) -> Result<LoadedRuleFont, Unavailable> {
        let axes: [String: Double]
        switch reference.identity {
        case let .file(_, _, variations), let .process(_, variations): axes = variations
        }
        guard let canonical = Self.canonicalAxes(axes) else { return .failure(.identityMismatch) }
        let variation = Dictionary(uniqueKeysWithValues: canonical.map { (NSNumber(value: $0.key), NSNumber(value: $0.value)) })
        let size: CGFloat = 32
        switch location {
        case let .file(url, faceIndex):
            // Mapped, so a large font costs address space, not memory.
            guard let bytes = try? Data(contentsOf: url, options: .alwaysMapped) else { return .failure(.missingFile) }
            // Only a single-face sfnt: named variable instances aren't collection faces.
            guard faceIndex == 0, Self.isSingleFaceSFNT(bytes) else { return .failure(.identityMismatch) }
            let data = bytes as CFData
            guard let provider = CGDataProvider(data: data), let graphics = CGFont(provider) else { return .failure(.identityMismatch) }
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: variation] as CFDictionary)
            let font = CTFontCreateWithGraphicsFont(graphics, size, nil, descriptor)
            let loaded = LoadedRuleFont(reference: font, graphics: graphics, dataProvider: provider, data: data, descriptor: descriptor)
            return verify(loaded, reference: reference, variation: variation)
        case let .installed(name):
            let named = CTFontDescriptorCreateWithNameAndSize(name as CFString, 0)
            // An unknown name silently becomes another font; refuse that.
            guard CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(named, size, nil)) as String == name else {
                return .failure(.missingFile)
            }
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(named, [kCTFontVariationAttribute: variation] as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            let loaded = LoadedRuleFont(reference: font, graphics: nil, dataProvider: nil, data: nil, descriptor: descriptor)
            return verify(loaded, reference: reference, variation: variation)
        }
    }

    /// Without variations the PostScript name must match; with them, every
    /// requested coordinate must be the one CoreText actually uses.
    private func verify(_ loaded: LoadedRuleFont, reference: FontFaceReference, variation: [NSNumber: NSNumber]) -> Result<LoadedRuleFont, Unavailable> {
        if variation.isEmpty {
            return loaded.postScriptName == reference.postScriptName ? .success(loaded) : .failure(.identityMismatch)
        }
        let effective = Self.effectiveCoordinates(loaded.reference)
        for (axis, requested) in variation {
            guard let actual = effective[axis]?.doubleValue, abs(actual - requested.doubleValue) <= 0.0001 else {
                return .failure(.identityMismatch)
            }
        }
        return .success(loaded)
    }

    static func isSingleFaceSFNT(_ data: Data) -> Bool {
        [[0, 1, 0, 0], [0x4F, 0x54, 0x54, 0x4F], [0x74, 0x72, 0x75, 0x65]].contains(Array(data.prefix(4)))
    }

    /// OpenType tags or CoreText's decimal identifiers as numeric axis ids.
    static func canonicalAxes(_ axes: [String: Double]) -> [UInt32: Double]? {
        var result: [UInt32: Double] = [:]
        for (key, value) in axes {
            let identifier: UInt32
            if let numeric = UInt32(key) {
                identifier = numeric
            } else {
                let bytes = Array(key.utf8)
                guard bytes.count == 4, bytes.allSatisfy({ (32...126).contains($0) }) else { return nil }
                identifier = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            }
            guard value.isFinite, result[identifier].map({ $0 == value }) ?? true else { return nil }
            result[identifier] = value
        }
        return result
    }

    /// CoreText reports only non-default coordinates; an absent one is the
    /// axis default, so start from the defaults.
    static func effectiveCoordinates(_ font: CTFont) -> [NSNumber: NSNumber] {
        var result: [NSNumber: NSNumber] = [:]
        if let definitions = CTFontCopyVariationAxes(font) as? [[String: Any]] {
            for definition in definitions {
                guard let axis = definition[kCTFontVariationAxisIdentifierKey as String] as? NSNumber,
                      let value = definition[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber,
                      value.doubleValue.isFinite else { continue }
                result[axis] = value
            }
        }
        if let overrides = CTFontCopyVariation(font) as? [NSNumber: NSNumber] {
            for (axis, value) in overrides where value.doubleValue.isFinite { result[axis] = value }
        }
        return result
    }
}

extension FontFaceReference {
    /// The face's name in previews: its family, plus the style unless it's Regular.
    var displayName: String {
        style.isEmpty || style == "Regular" || family.hasSuffix(style) ? family : family + " " + style
    }
}
#endif
