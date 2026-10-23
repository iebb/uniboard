#if canImport(UIKit)
import SwiftUI
import UIKit
import CoreText

/// The specimen is not SwiftUI.Text: the exact line which passes verification is drawn.
struct VerifiedFontPreview: UIViewRepresentable {
    let face: FontFaceRecord
    let inspection: FontInspection
    var pointSize: CGFloat = 64

    func makeUIView(context: Context) -> VerifiedFontLineView { VerifiedFontLineView() }
    func updateUIView(_ uiView: VerifiedFontLineView, context: Context) {
        uiView.configure(face: face, inspection: inspection, pointSize: pointSize)
    }
}

@MainActor
final class VerifiedFontLineView: UIView {
    private struct Configuration: Equatable {
        let face: FontFaceRecord
        let original: Data
        let preview: Data
        let name: Data
        let presentation: FontPresentation
        let scaffold: FontScaffold
        let size: CGFloat
        let revision: String
    }
    private var configuration: Configuration?
    private(set) var shapingCount = 0
    private var contentBounds = CGRect.zero
    private var line: CTLine?
    private var ascent: CGFloat = 0
    private var descent: CGFloat = 0
    private var lineWidth: CGFloat = 0
    private let unavailable = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        unavailable.text = "Preview unavailable"
        unavailable.font = .preferredFont(forTextStyle: .footnote)
        unavailable.adjustsFontForContentSizeCategory = true
        unavailable.textColor = .secondaryLabel
        unavailable.textAlignment = .center
        unavailable.numberOfLines = 0
        addSubview(unavailable)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(face: FontFaceRecord, inspection: FontInspection, pointSize: CGFloat, provider: any FontInventoryProviding = PublicFontInventory()) {
        let size = pointSize.isFinite ? min(512, max(1, pointSize)) : 64
        let key = Configuration(face: face, original: Data(inspection.originalText.utf8), preview: Data(inspection.previewText.utf8), name: Data(inspection.characterName.utf8), presentation: inspection.presentation, scaffold: inspection.scaffold, size: size, revision: CustomFontStore.shared.revision + "|" + UnicodeFontDownloadStore.shared.revision)
        guard configuration != key else { return }
        configuration = key
        shapingCount += 1
        // Confined to main actor; scan never transports a CTLine/CTFont here.
        let result = FontLineVerifier.line(face: face, inspection: inspection, size: size, provider: provider)
        line = result.1
        ascent = 0; descent = 0; lineWidth = 0
        contentBounds = .zero
        if let line {
            lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let typographic = CGRect(x: 0, y: -descent, width: lineWidth, height: ascent + descent)
            let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            let image = CTLineGetImageBounds(line, nil)
            contentBounds = typographic
            if !ink.isNull && !ink.isInfinite { contentBounds = contentBounds.union(ink) }
            if !image.isNull && !image.isInfinite { contentBounds = contentBounds.union(image) }
        }
        unavailable.isHidden = line != nil
        accessibilityLabel = "\(face.family), \(face.style), preview of \(inspection.characterName)"
        accessibilityValue = line == nil ? "Preview unavailable" : "Available in the app only"
        invalidateIntrinsicContentSize(); setNeedsDisplay()
    }
    override var intrinsicContentSize: CGSize {
        CGSize(width: max(96, contentBounds.width + 24), height: max(96, contentBounds.height + 24))
    }
    override func layoutSubviews() { super.layoutSubviews(); unavailable.frame = bounds.insetBy(dx: 8, dy: 8) }
    var fittedContentRect: CGRect {
        let width = max(0, bounds.width - 24), height = max(0, bounds.height - 24)
        let scale = min(1, width / max(1, contentBounds.width), height / max(1, contentBounds.height))
        let size = CGSize(width: contentBounds.width * scale, height: contentBounds.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    override func draw(_ rect: CGRect) {
        guard let line, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.setFillColor(UIColor.label.cgColor)
        let availableWidth = max(0, bounds.width - 24), availableHeight = max(0, bounds.height - 24)
        guard availableWidth > 0, availableHeight > 0 else { return }
        let scale = min(1, availableWidth / max(1, contentBounds.width), availableHeight / max(1, contentBounds.height))
        let fitted = fittedContentRect
        let x = fitted.minX - contentBounds.minX * scale
        let y = fitted.minY - contentBounds.minY * scale
        context.translateBy(x: x, y: y)
        context.scaleBy(x: scale, y: scale)
        context.textPosition = .zero
        CTLineDraw(line, context)
    }
}
#endif
