#if canImport(UIKit)
import CoreText
import UIKit

/// Capture before recognition/slop and never retain a UITouch or UIEvent.
private final class QueryTapRecognizer: UITapGestureRecognizer {
    var capture: ((UITouch) -> UUID?)?
    var finish: ((UUID) -> Void)?
    private(set) var interactionToken: UUID?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { interactionToken = capture?(touch) }
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let token = interactionToken
        super.touchesEnded(touches, with: event)
        if let token { finish?(token) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        let token = interactionToken
        super.touchesCancelled(touches, with: event)
        if let token { finish?(token) }
    }
    override func reset() { super.reset(); interactionToken = nil }
}
private final class QueryPanRecognizer: UIPanGestureRecognizer {
    var capture: ((UITouch) -> UUID?)?
    var finish: ((UUID) -> Void)?
    private(set) var interactionToken: UUID?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { interactionToken = capture?(touch) }
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let token = interactionToken
        super.touchesEnded(touches, with: event)
        if let token { finish?(token) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        let token = interactionToken
        super.touchesCancelled(touches, with: event)
        if let token { finish?(token) }
    }
    override func reset() { super.reset(); interactionToken = nil }
}

final class KeyboardQueryControl: UIControl {
    private let magnifier = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let viewport = UIView()
    private let label = UILabel()
    private let caret = UIView()
    private var line: CTLine?
    private var lineWidth: CGFloat = 0
    private var horizontalOffset: CGFloat = 0
    private var query = ""
    private var caretUTF16Offset = 0
    private var graphemeOffsets = [0]
    private var isEditingQuery = false
    private var isEmojiScope = false
    private let interaction = KeyboardQueryInteraction()
    private var controlsEnabled = false
    private var tapRecognizer: QueryTapRecognizer?
    private var dragRecognizer: QueryPanRecognizer?
    private let textInset: CGFloat = 2

    override var canBecomeFirstResponder: Bool { false }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 40)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        semanticContentAttribute = .forceLeftToRight
        tintColor = .systemOrange
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isUserInteractionEnabled = false
        isEnabled = false
        isHidden = true
        accessibilityIdentifier = "keyboard.search"

        magnifier.contentMode = .scaleAspectFit
        magnifier.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        magnifier.isUserInteractionEnabled = false
        addSubview(magnifier)

        // This is deliberately not a UIScrollView. A query is foreground
        // control text; automatic scroll-edge effects can blur it under glass.
        // Move the clipped label directly to reveal the local insertion point.
        viewport.isUserInteractionEnabled = false
        viewport.backgroundColor = .clear
        viewport.isOpaque = false
        viewport.clipsToBounds = true
        viewport.accessibilityElementsHidden = true
        addSubview(viewport)
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.textAlignment = .left
        label.semanticContentAttribute = .forceLeftToRight
        label.isUserInteractionEnabled = false
        viewport.addSubview(label)
        caret.layer.cornerRadius = 1
        caret.isUserInteractionEnabled = false
        viewport.addSubview(caret)

        let tap = QueryTapRecognizer(target: self, action: #selector(tapped(_:)))
        let drag = QueryPanRecognizer(target: self, action: #selector(dragged(_:)))
        tapRecognizer = tap
        dragRecognizer = drag
        let capture: (UITouch) -> UUID? = { [weak self] touch in self?.interaction.beginPhysicalTouch(owner: touch) }
        let finish: (UUID) -> Void = { [weak self] token in
            // Target delivery completes within the input event. Defer fallback
            // cleanup so a normal tap is not lost to raw-touch cancellation.
            DispatchQueue.main.async { [weak self] in self?.interaction.endPhysicalTouch(token: token) }
        }
        tap.capture = capture; drag.capture = capture
        tap.finish = finish; drag.finish = finish
        drag.maximumNumberOfTouches = 1
        tap.require(toFail: drag)
        addGestureRecognizer(tap)
        addGestureRecognizer(drag)

        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move to beginning of search") { [weak self] _ in
                guard let self else { return false }
                guard self.activateFresh(caret: 0) else { return false }
                self.announceCaretPosition()
                return true
            },
            UIAccessibilityCustomAction(name: "Move to end of search") { [weak self] _ in
                guard let self else { return false }
                guard self.activateFresh(caret: self.query.utf16.count) else { return false }
                self.announceCaretPosition()
                return true
            }
        ]
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(query: String, caretUTF16Offset: Int, isEditing: Bool, isEmojiScope: Bool,
                   contextIdentifier: UUID, enabled: Bool,
                   actionFactory: @escaping KeyboardQueryInteraction.ActionFactory) {
        let textChanged = !self.query.utf16.elementsEqual(query.utf16) || self.isEmojiScope != isEmojiScope || label.attributedText == nil
        let textScopeChanged = !self.query.utf16.elementsEqual(query.utf16) || self.isEmojiScope != isEmojiScope
        let enabledChanged = controlsEnabled != enabled
        self.controlsEnabled = enabled
        let cancelled = interaction.configure(contextIdentifier: contextIdentifier, enabled: enabled, actionFactory: actionFactory)
        if !enabled { interaction.cancelAll() }
        if textScopeChanged { _ = interaction.cancelCurrentAction() }
        if cancelled || textScopeChanged || enabledChanged || !enabled { cancelRecognizers() }
        self.isUserInteractionEnabled = enabled
        isEnabled = enabled
        isAccessibilityElement = enabled
        accessibilityElementsHidden = !enabled
        isHidden = !enabled
        self.query = query
        self.caretUTF16Offset = KeyboardQueryPolicy.normalizedUTF16Offset(caretUTF16Offset, in: query)
        self.isEditingQuery = isEditing
        self.isEmojiScope = isEmojiScope
        if textChanged { rebuildLine() }
        accessibilityLabel = isEmojiScope ? "Search emoji sequences" : "Search Unicode characters"
        accessibilityValue = query.isEmpty ? "No query" : query
        accessibilityTraits = query.isEmpty ? [.button] : [.button, .adjustable]
        accessibilityHint = isEditing
            ? "Tap or drag within the search text to move its cursor. Swipe up or down to move by one character."
            : "Double tap to expand the search keys."
        updateAppearance()
        setNeedsLayout()
    }

    private func rebuildLine() {
        graphemeOffsets = KeyboardQueryPolicy.utf16Boundaries(in: query)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.baseWritingDirection = .leftToRight
        paragraph.lineBreakMode = .byClipping
        let font = UIFont.systemFont(ofSize: 14, weight: query.isEmpty ? .regular : .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: query.isEmpty ? UIColor.secondaryLabel : UIColor.label
        ]
        let displayed = query.isEmpty ? (isEmojiScope ? "Search emoji" : "Search Unicode") : query
        let attributed = NSAttributedString(string: displayed, attributes: attributes)
        label.font = font
        label.attributedText = attributed
        line = CTLineCreateWithAttributedString(attributed)
        lineWidth = line.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) } ?? 0
        if !lineWidth.isFinite { lineWidth = 0 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = renderingScale
        // The remote keyboard can attach to a different display. Keep its
        // text rasterization and final positions on that display's pixel grid.
        for view in [self, viewport, label, magnifier, caret] where view.contentScaleFactor != scale {
            view.contentScaleFactor = scale
        }
        let width = bounds.width.isFinite ? max(0, bounds.width) : 0
        let height = bounds.height.isFinite ? max(0, bounds.height) : 0
        magnifier.frame = CGRect(x: aligned(11), y: aligned(max(0, (height - 16) / 2)), width: 16, height: 16)
        let viewportWidth = max(0, aligned(width - 34 - 8))
        viewport.frame = CGRect(x: aligned(34), y: 0, width: viewportWidth, height: height)
        let contentWidth = max(viewportWidth, KeyboardQueryViewportPolicy.pixelAligned(max(0, lineWidth), scale: scale, rule: .up) + textInset * 2 + 2)
        let caretX = textInset + caretOffset(for: caretUTF16Offset)
        revealCaret(at: caretX, viewportWidth: viewportWidth, contentWidth: contentWidth)
        let labelX = aligned(textInset - horizontalOffset)
        label.frame = CGRect(x: labelX, y: 0, width: max(0, contentWidth - textInset * 2), height: height)
        caret.frame = CGRect(x: aligned(labelX + caretOffset(for: caretUTF16Offset)),
                             y: aligned(max(0, (height - 18) / 2)), width: 2, height: min(18, height))
    }

    private func revealCaret(at x: CGFloat, viewportWidth: CGFloat, contentWidth: CGFloat) {
        horizontalOffset = KeyboardQueryViewportPolicy.horizontalOffset(
            caretX: x, previousOffset: horizontalOffset, viewportWidth: viewportWidth,
            contentWidth: contentWidth, scale: renderingScale)
    }

    private var renderingScale: CGFloat {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        return scale.isFinite && scale > 0 ? scale : 1
    }

    private func aligned(_ value: CGFloat) -> CGFloat {
        KeyboardQueryViewportPolicy.pixelAligned(value, scale: renderingScale)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { interaction.cancelAll(); cancelRecognizers() }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    private func caretOffset(for index: Int) -> CGFloat {
        guard !query.isEmpty, let line else { return 0 }
        let offset = CTLineGetOffsetForStringIndex(line, min(max(0, index), query.utf16.count), nil)
        return offset.isFinite ? offset : 0
    }

    private func index(at point: CGPoint) -> Int {
        guard !query.isEmpty, let line else { return 0 }
        let x = point.x - viewport.frame.minX - label.frame.minX
        guard x.isFinite else { return caretUTF16Offset }
        let hit = CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
        if hit == kCFNotFound {
            // Logical beginning/end can be on opposite visual edges in RTL
            // runs. Pick the actual closest caret, rather than assuming LTR.
            return KeyboardQueryPolicy.nearestVisualBoundary(to: x, boundaries: graphemeOffsets, offset: caretOffset)
        }
        let index = min(max(0, hit), query.utf16.count)
        if graphemeOffsets.contains(index) { return index }
        // Core Text can return an index inside a composed character. Choose
        // its nearest visual edge; the model also validates the boundary.
        let next = graphemeOffsets.first(where: { $0 > index }) ?? query.utf16.count
        let previous = graphemeOffsets.last(where: { $0 < index }) ?? 0
        return KeyboardQueryPolicy.nearestVisualBoundary(to: x, boundaries: [previous, next], offset: caretOffset)
    }

    @objc private func tapped(_ gesture: QueryTapRecognizer) {
        guard let token = gesture.interactionToken else { return }
        defer { interaction.endPhysicalTouch(token: token) }
        let point = gesture.location(in: self)
        let target = !query.isEmpty && point.x >= viewport.frame.minX ? index(at: point) : nil
        _ = performCaretAction(target, token: token)
    }

    @objc private func dragged(_ gesture: QueryPanRecognizer) {
        guard let token = gesture.interactionToken else { return }
        switch gesture.state {
        case .began, .changed:
            _ = performCaretAction(query.isEmpty ? nil : index(at: gesture.location(in: self)), token: token)
        case .ended, .cancelled, .failed: interaction.endPhysicalTouch(token: token)
        default: break
        }
    }

    private func commitLocalCaret(_ target: Int?) {
        if let target { caretUTF16Offset = KeyboardQueryPolicy.normalizedUTF16Offset(target, in: query) }
        setNeedsLayout()
    }
    @discardableResult
    private func performCaretAction(_ target: Int?, token: UUID) -> Bool {
        let accepted = interaction.perform(caret: target, token: token) { self.commitLocalCaret(target) }
        if !accepted, interaction.physicalToken == token { cancelRecognizers() }
        return accepted
    }
    private func cancelRecognizers() {
        let recognizers: [UIGestureRecognizer?] = [tapRecognizer, dragRecognizer]
        for recognizer in recognizers.compactMap({ $0 }) {
            recognizer.isEnabled = false
            recognizer.isEnabled = controlsEnabled
        }
    }
    @discardableResult
    private func activateFresh(caret target: Int?) -> Bool {
        _ = interaction.cancelCurrentAction()
        cancelRecognizers()
        return interaction.activateFresh(caret: target) { self.commitLocalCaret(target) }
    }

    override func accessibilityActivate() -> Bool { activateFresh(caret: nil) }
    override func accessibilityIncrement() {
        if activateFresh(caret: graphemeOffsets.first(where: { $0 > caretUTF16Offset }) ?? query.utf16.count) {
            announceCaretPosition()
        }
    }
    override func accessibilityDecrement() {
        if activateFresh(caret: graphemeOffsets.last(where: { $0 < caretUTF16Offset }) ?? 0) {
            announceCaretPosition()
        }
    }

    private func announceCaretPosition() {
        let message: String
        if caretUTF16Offset == 0 { message = "Beginning of search" }
        else if caretUTF16Offset == query.utf16.count { message = "End of search" }
        else { message = "Search cursor at character \((graphemeOffsets.firstIndex(of: caretUTF16Offset) ?? 0) + 1)" }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func updateAppearance() {
        magnifier.tintColor = isEditingQuery ? tintColor : .secondaryLabel
        caret.backgroundColor = tintColor
        caret.isHidden = !isEditingQuery
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateAppearance()
    }
}
#endif
