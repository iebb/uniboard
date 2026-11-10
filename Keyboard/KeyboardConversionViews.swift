import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Solid informative ink, shared by language shelves and conversion panels.
/// Do not apply opacity: these labels must remain readable on the keyboard tray.
enum KeyboardLanguageInformativeInk {
    /// UIKit form, also used for an unreadable language in the space-bar list.
    /// Increase Contrast gets a stronger variant of the same ink (no glyph).
    static let secondaryUI = UIColor { traits in
        let high = traits.accessibilityContrast == .high
        return traits.userInterfaceStyle == .dark
            ? (high ? UIColor(red: 210.0 / 255, green: 210.0 / 255, blue: 217.0 / 255, alpha: 1) // #D2D2D9
                : UIColor(red: 177.0 / 255, green: 177.0 / 255, blue: 186.0 / 255, alpha: 1)) // #B1B1BA
            : (high ? UIColor(red: 64.0 / 255, green: 64.0 / 255, blue: 72.0 / 255, alpha: 1) // #404048
                : UIColor(red: 98.0 / 255, green: 98.0 / 255, blue: 107.0 / 255, alpha: 1)) // #62626B
    }
    static let secondary = Color(uiColor: secondaryUI)
}

/// The controller measures the same short caption and scaled font rendered by
/// the shelf. Width is the actual shelf container, not a device/idiom preset.
enum KeyboardConversionShelfMetrics {
    static func caption(for mode: LanguageInputMode) -> String {
        switch mode {
        case .direct: return "Direct Typing"
        case .japaneseRomaji: return "Japanese"
        case .mandarinPinyin: return "Mandarin"
        case .koreanRomaja: return "Romaja"
        case .koreanTwoSetHangul: return "Two-Set Hangul"
        }
    }

    static func regularCaptionFits(mode: LanguageInputMode, containerWidth: CGFloat,
                                   traits: UITraitCollection) -> Bool {
        // UnicodeKeyboardView caps Dynamic Type at xxxLarge; match its
        // @ScaledMetric(relativeTo: .footnote) rather than measuring a larger font.
        let category = traits.preferredContentSizeCategory.isAccessibilityCategory
            ? UIContentSizeCategory.extraExtraExtraLarge : traits.preferredContentSizeCategory
        let captionTraits = UITraitCollection(preferredContentSizeCategory: category)
        let font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: UIFont.systemFont(ofSize: 13), compatibleWith: captionTraits)
        let width = ceil((caption(for: mode) as NSString).size(withAttributes: [.font: font]).width)
        return KeyboardCompositionLayoutPolicy.regularCaptionFits(
            captionWidth: width, availableLineWidth: containerWidth - 16)
    }
}

/// Candidate-only tokens: app and generic recovery helpers retain their own ink.
enum KeyboardCandidateInk {
    static let secondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 177.0 / 255, green: 177.0 / 255, blue: 186.0 / 255, alpha: 1)
            : UIColor(red: 84.0 / 255, green: 84.0 / 255, blue: 93.0 / 255, alpha: 1)
    })
    static let divider = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 99.0 / 255, green: 99.0 / 255, blue: 107.0 / 255, alpha: 1)
            : UIColor(red: 138.0 / 255, green: 142.0 / 255, blue: 152.0 / 255, alpha: 1)
    })
}

/// No persistent selection wash. This style is also used by actionable English choices.
struct KeyboardCandidateButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                        .allowsHitTesting(false)
                }
            }
    }
}

struct KeyboardCandidateDivider: View {
    var vertical = true
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(KeyboardCandidateInk.divider)
            .frame(width: vertical ? 1 / displayScale : nil,
                   height: vertical ? 20 : 1 / displayScale)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Shared output typography; strip labels keep their natural width, expanded labels wrap.
struct KeyboardCandidateText: View {
    let output: String
    var pending = false
    var expanded = false
    @ScaledMetric(relativeTo: .title3) private var outputSize = 20.0

    var body: some View {
        Text(verbatim: output)
            .font(.system(size: outputSize, weight: pending ? .semibold : .regular))
            .lineLimit(expanded ? nil : 1)
            .fixedSize(horizontal: !expanded, vertical: expanded)
            .padding(.horizontal, 12)
            .padding(.vertical, expanded ? 8 : 0)
            .frame(minWidth: 44, maxWidth: expanded ? .infinity : nil,
                   minHeight: 44, maxHeight: expanded ? nil : 44, alignment: .leading)
            .foregroundStyle(Color(uiColor: .label))
            .contentShape(Rectangle())
    }
}

/// Presentation snapshots never authorize a host write. Even a frozen action still
/// carries the originally displayed token to the controller's existing validator.
private struct ConversionDisplaySnapshot {
    let mode: LanguageInputMode
    let rawInput: String
    let preedit: String
    let candidates: [LanguageConversionCandidate]
    let token: LanguageCompositionToken
    let statusText: String?
    let onChoose: (String, LanguageCompositionToken) -> Void
    let onLiteral: () -> Void
    var onCancel: () -> Void = {}

    var outputs: [LanguageConversionCandidate] {
        rawInput.isEmpty ? [] : candidates.filter { $0.source != .literal }
    }

    // Byte arrays deliberately distinguish canonically equivalent original inputs.
    struct Generation: Equatable {
        let token: LanguageCompositionToken
        let raw: [UInt8]
        let preedit: [UInt8]
        let candidates: [LanguageConversionCandidate]
        let status: String?
    }
    var generation: Generation {
        Generation(token: token, raw: Array(rawInput.utf8), preedit: Array(preedit.utf8),
                   candidates: candidates, status: statusText)
    }
}

/// A passive observer, not a competing tap/drag recognizer. Counting actual
/// touches keeps a generation frozen until *all* fingers lift, including cancelled
/// scrolls. The window attachment sees SwiftUI descendants; the region filter
/// restricts observation to this panel and never swallows keyboard/key touches.
private struct ConversionTouchObserver: UIViewRepresentable {
    let onActive: (Bool) -> Void

    func makeUIView(context: Context) -> ConversionTouchRegion {
        let view = ConversionTouchRegion()
        view.isUserInteractionEnabled = false
        view.onActive = onActive
        return view
    }

    func updateUIView(_ view: ConversionTouchRegion, context: Context) {
        view.onActive = onActive
    }

    static func dismantleUIView(_ view: ConversionTouchRegion, coordinator: ()) {
        view.disconnect()
    }
}

private final class ConversionTouchRegion: UIView {
    var onActive: (Bool) -> Void = { _ in }
    private var observer: ConversionTouchRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        disconnect()
        if let window {
            let observer = ConversionTouchRecognizer(region: self)
            self.observer = observer
            window.addGestureRecognizer(observer)
        }
    }

    func disconnect() {
        if let observer {
            observer.view?.removeGestureRecognizer(observer)
            observer.finishObservation()
        }
        observer = nil
    }
}

private final class ConversionTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var region: ConversionTouchRegion?
    private var activeTouches = Set<ObjectIdentifier>()

    init(region: ConversionTouchRegion) {
        self.region = region
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let region, region.window != nil else { return false }
        return region.bounds.contains(touch.location(in: region))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let wasEmpty = activeTouches.isEmpty
        activeTouches.formUnion(touches.map { ObjectIdentifier($0) })
        if wasEmpty { region?.onActive(true) }
        state = state == .possible ? .began : .changed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { remove(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { remove(touches) }

    private func remove(_ touches: Set<UITouch>) {
        activeTouches.subtract(touches.map { ObjectIdentifier($0) })
        if activeTouches.isEmpty {
            region?.onActive(false)
            state = .ended
        } else { state = .changed }
    }

    func finishObservation() {
        if !activeTouches.isEmpty { region?.onActive(false) }
        activeTouches.removeAll()
    }

    override func reset() {
        finishObservation()
        super.reset()
    }
}

/// Freeze complete labels, order, tokens and closures, not just candidate IDs.
/// Releasing actions run before publishing a queued generation to the strip/grid.
private struct ConversionTouchSnapshotView<Content: View>: View {
    let latest: ConversionDisplaySnapshot
    let content: (ConversionDisplaySnapshot, Bool) -> Content
    @State private var displayed: ConversionDisplaySnapshot
    @State private var newest: ConversionDisplaySnapshot
    @State private var isTouching = false
    @State private var touchSequence = 0

    init(latest: ConversionDisplaySnapshot,
         @ViewBuilder content: @escaping (ConversionDisplaySnapshot, Bool) -> Content) {
        self.latest = latest
        self.content = content
        _displayed = State(initialValue: latest)
        _newest = State(initialValue: latest)
    }

    var body: some View {
        content(displayed, isTouching)
            .background(ConversionTouchObserver(onActive: receiveTouch))
            .onChange(of: latest.generation) { _, _ in
                newest = latest
                if !isTouching { displayed = latest }
            }
    }

    private func receiveTouch(_ active: Bool) {
        touchSequence += 1
        let sequence = touchSequence
        if active { isTouching = true }
        else {
            DispatchQueue.main.async {
                guard touchSequence == sequence else { return }
                displayed = newest
                isTouching = false
            }
        }
    }
}

/// Presentation only. The controller owns the unchanged 74/44-point fit policy.
struct KeyboardConversionShelf: View {
    let mode: LanguageInputMode
    let rawInput: String
    let preedit: String
    let candidates: [LanguageConversionCandidate]
    let token: LanguageCompositionToken
    let statusText: String?
    let height: CGFloat
    let onChoose: (String, LanguageCompositionToken) -> Void
    let onLiteral: () -> Void
    let onExpand: () -> Void

    @ScaledMetric(relativeTo: .body) private var preeditSize = 17.0
    @ScaledMetric(relativeTo: .footnote) private var captionSize = 13.0
    private var compact: Bool { height < 74 }

    var body: some View {
        ConversionTouchSnapshotView(latest: ConversionDisplaySnapshot(
            mode: mode, rawInput: rawInput, preedit: preedit, candidates: candidates,
            token: token, statusText: statusText, onChoose: onChoose, onLiteral: onLiteral)) { display, touching in
            shelfContent(display, touching: touching)
        }
    }

    @ViewBuilder private func shelfContent(_ display: ConversionDisplaySnapshot, touching: Bool) -> some View {
        // Keep the regular shelf's trailing slot stable while idle.
        let hidesExpansion = !compact && display.rawInput.isEmpty
        let hidesIdleShelf = display.rawInput.isEmpty && display.statusText == nil
        if display.mode == .koreanTwoSetHangul {
            KoreanHangulWordRow(display: display, touching: touching)
                .frame(height: 44)
                .buttonStyle(KeyboardCandidateButtonStyle())
                .overlay(alignment: .bottom) { KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8) }
                .accessibilityHidden(hidesIdleShelf)
                .allowsHitTesting(!hidesIdleShelf)
        } else {
        VStack(spacing: 0) {
            if !compact {
                HStack(spacing: 8) {
                    Text(KeyboardConversionShelfMetrics.caption(for: display.mode))
                        .font(.system(size: captionSize))
                        .foregroundStyle(KeyboardCandidateInk.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("keyboard.conversion.modeCaption")
                    GeometryReader { viewport in
                        ScrollView(.horizontal) {
                            Text(display.preedit.isEmpty ? display.rawInput : display.preedit)
                                .font(.system(size: preeditSize))
                                .foregroundStyle(KeyboardCandidateInk.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                // Fill spare space, but never constrain the overflow.
                                .frame(minWidth: viewport.size.width, minHeight: viewport.size.height, alignment: .leading)
                        }
                        .defaultScrollAnchor(.trailing)
                        .conversionUnmaskedScrollEdges()
                        .scrollIndicators(.hidden)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Unfinished text")
                        .accessibilityValue(conversionUnfinishedValue(rawInput: display.rawInput, preedit: display.preedit))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .opacity(display.rawInput.isEmpty ? 0 : 1)
                .accessibilityHidden(display.rawInput.isEmpty)
                .allowsHitTesting(!display.rawInput.isEmpty)
            }
            HStack(spacing: 0) {
                if compact && display.rawInput.isEmpty {
                    Text(display.statusText ?? "")
                        .font(.footnote)
                        .foregroundStyle(KeyboardCandidateInk.secondary)
                        .padding(.leading, 12)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    if compact {
                        compactUnfinishedButton(display, touching: touching)
                        KeyboardCandidateDivider()
                    }
                    ConversionCandidateStrip(display: display, touching: touching, compact: compact)
                    KeyboardCandidateDivider()
                        .opacity(hidesExpansion ? 0 : 1)
                    Button(action: onExpand) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("More Choices")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onExpand() }
                    .opacity(hidesExpansion ? 0 : 1)
                    .disabled(hidesExpansion)
                    .accessibilityHidden(hidesExpansion)
                }
            }
            .frame(height: 44)
        }
        .buttonStyle(KeyboardCandidateButtonStyle())
        .foregroundStyle(Color(uiColor: .label))
        // Transparent: the controller already supplies the actual KeyboardTray.
        .frame(height: compact ? 44 : 74)
        .clipped()
        .overlay(alignment: .bottom) {
            KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversion Choices")
        .accessibilityHidden(hidesIdleShelf)
        .allowsHitTesting(!hidesIdleShelf)
        }
    }

    private func compactUnfinishedButton(_ display: ConversionDisplaySnapshot, touching: Bool) -> some View {
        let unfinished = display.preedit.isEmpty ? display.rawInput : display.preedit
        // Measure the same already-scaled font as Text. A maxWidth alone would
        // let a horizontal ScrollView greedily take all 160 points, even for “ni”.
        let textWidth = ceil((unfinished as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: preeditSize)
        ]).width)
        let viewportWidth = min(160, max(44, textWidth + 12 + 8))
        return ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                Button(action: onExpand) {
                    Text(verbatim: unfinished)
                        .font(.system(size: preeditSize))
                        .foregroundStyle(KeyboardCandidateInk.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, 12)
                        .padding(.trailing, 8)
                        .frame(minWidth: viewportWidth, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .id("compact-preedit")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Unfinished text")
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(conversionUnfinishedValue(rawInput: display.rawInput, preedit: display.preedit))
                .accessibilityHint("Opens Conversion Choices")
            }
            .defaultScrollAnchor(.trailing)
            .conversionUnmaskedScrollEdges()
            .scrollIndicators(.hidden)
            .frame(width: viewportWidth, height: 44)
            .onAppear {
                if !touching { scroll.scrollTo("compact-preedit", anchor: .trailing) }
            }
            .onChange(of: display.generation) { _, _ in
                if !touching { scroll.scrollTo("compact-preedit", anchor: .trailing) }
            }
        }
        .frame(width: viewportWidth, height: 44)
    }
}

/// One regular-weight word, never a literal key-ID chip or a default/More strip.
/// The final scalar is the composer’s active modern syllable/compatibility jamo.
private struct KoreanHangulWordRow: View {
    let display: ConversionDisplaySnapshot
    let touching: Bool
    private var word: String { display.outputs.first?.output ?? "" }
    private var completed: String { String(word.dropLast()) }

    var body: some View {
        GeometryReader { viewport in
            if let candidate = display.outputs.first {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        Button { display.onChoose(candidate.id, display.token) } label: {
                            HStack(spacing: 0) {
                                Text(verbatim: String(word.dropLast()))
                                    .font(.system(size: 20, weight: .regular))
                                    .fixedSize(horizontal: true, vertical: false)
                                Text(verbatim: String(word.suffix(1)))
                                    .font(.system(size: 20, weight: .regular))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().frame(height: 1).offset(y: 2)
                                    }
                                Color.clear.frame(width: 1, height: 1).id("hangul-end")
                            }
                            .padding(.horizontal, 12)
                            .frame(minWidth: viewport.size.width, minHeight: 44, alignment: .leading)
                            .foregroundStyle(Color(uiColor: .label))
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Insert \(word)")
                        .accessibilityIdentifier("keyboard.conversion.hangulWord")
                    }
                    .scrollIndicators(.hidden)
                    .conversionUnmaskedScrollEdges()
                    .onAppear { if !touching { scroll.scrollTo("hangul-end", anchor: .trailing) } }
                    .onChange(of: display.generation) { _, _ in
                        if !touching { scroll.scrollTo("hangul-end", anchor: .trailing) }
                    }
                    .onChange(of: touching) { _, active in
                        if !active { scroll.scrollTo("hangul-end", anchor: .trailing) }
                    }
                }
            } else {
                Text(display.statusText ?? (display.rawInput.isEmpty ? "" : "Converting…"))
                    .font(.system(size: 13))
                    .foregroundStyle(KeyboardCandidateInk.secondary)
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .frame(height: 44)
        .task(id: completed) {
            guard !completed.isEmpty, UIAccessibility.isVoiceOverRunning else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            UIAccessibility.post(notification: .announcement, argument: completed)
        }
    }
}

private struct ConversionPendingFrame: Equatable {
    let generation: ConversionDisplaySnapshot.Generation
    let rect: CGRect
}

private struct ConversionPendingFrameKey: PreferenceKey {
    static var defaultValue: ConversionPendingFrame? { nil }
    static func reduce(value: inout ConversionPendingFrame?, nextValue: () -> ConversionPendingFrame?) {
        value = nextValue() ?? value
    }
}

private struct ConversionCandidateStrip: View {
    let display: ConversionDisplaySnapshot
    let touching: Bool
    let compact: Bool
    @Namespace private var viewportSpace
    @State private var pendingFrame: ConversionPendingFrame?
    @State private var revealRequest: ConversionDisplaySnapshot.Generation?
    @ScaledMetric(relativeTo: .title3) private var outputSize = 20.0

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        if !display.rawInput.isEmpty {
                            literalButton(rawInput: display.rawInput, action: display.onLiteral)
                            ForEach(display.outputs) { candidate in
                                KeyboardCandidateDivider()
                                ConversionCandidateButton(candidate: candidate, token: display.token,
                                    pending: candidate.id == display.outputs.first?.id,
                                    expanded: false, onChoose: display.onChoose)
                                    .id(candidate.id)
                                    .background {
                                        if candidate.id == display.outputs.first?.id {
                                            GeometryReader { cell in
                                                Color.clear.preference(key: ConversionPendingFrameKey.self,
                                                    value: ConversionPendingFrame(generation: display.generation,
                                                        rect: cell.frame(in: .named(viewportSpace))))
                                            }
                                        }
                                    }
                            }
                        }
                        if let message = display.statusText ?? (display.rawInput.isEmpty ? nil : (display.outputs.isEmpty ? "No matching conversion" : nil)) {
                            Text(message).font(.footnote)
                                .foregroundStyle(KeyboardCandidateInk.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.horizontal, compact ? 0 : 8)
                }
                .conversionUnmaskedScrollEdges()
                .scrollIndicators(.hidden)
                .coordinateSpace(name: viewportSpace)
                .onAppear { revealRequest = display.generation }
                .onChange(of: display.generation) { _, generation in
                    revealRequest = generation
                    revealIfNeeded(request: generation, frame: pendingFrame, width: viewport.size.width, scroll: scroll)
                }
                .onChange(of: revealRequest) { _, request in
                    revealIfNeeded(request: request, frame: pendingFrame, width: viewport.size.width, scroll: scroll)
                }
                .onPreferenceChange(ConversionPendingFrameKey.self) { frame in
                    pendingFrame = frame
                    revealIfNeeded(request: revealRequest, frame: frame, width: viewport.size.width, scroll: scroll)
                }
                .onChange(of: touching) { _, active in
                    if !active {
                        revealIfNeeded(request: revealRequest, frame: pendingFrame, width: viewport.size.width, scroll: scroll)
                    }
                }
            }
        }
        .frame(height: 44)
    }

    private func literalButton(rawInput: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: rawInput)
                .font(.system(size: outputSize, weight: .regular))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44, maxHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Insert exactly as typed: \(rawInput)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(rawInput)
        .accessibilityHint("Inserts the exact typed text")
    }

    private func revealIfNeeded(request: ConversionDisplaySnapshot.Generation?, frame: ConversionPendingFrame?,
                                width: CGFloat, scroll: ScrollViewProxy) {
        guard !touching, let request, let frame, request == display.generation,
              request == frame.generation, let first = display.outputs.first else { return }
        // Consume only a generation change, not ordinary scrolling preferences.
        revealRequest = nil
        if frame.rect.maxX <= 0 || frame.rect.minX >= width {
            scroll.scrollTo(first.id, anchor: .leading)
        }
    }
}

/// Contained in the existing owner bounds; no new keyboard/root height request.
struct KeyboardExpandedConversionView: View {
    let mode: LanguageInputMode
    let rawInput: String
    let preedit: String
    let candidates: [LanguageConversionCandidate]
    let token: LanguageCompositionToken
    let statusText: String?
    let height: CGFloat
    let onChoose: (String, LanguageCompositionToken) -> Void
    let onLiteral: () -> Void
    let onClose: () -> Void
    let onCancel: () -> Void
    let queuedPunctuation: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @AccessibilityFocusState private var focused: FocusTarget?
    @ScaledMetric(relativeTo: .title3) private var outputSize = 20.0
    @ScaledMetric(relativeTo: .body) private var cancelSize = 17.0
    private enum FocusTarget: Hashable { case preedit, candidate(String) }

    // Scoped to expanded Cancel text only; dark keeps its existing system rendering.
    private static let cancelInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemBlue.resolvedColor(with: traits)
            : UIColor(red: 0, green: 87.0 / 255, blue: 184.0 / 255, alpha: 1) // #0057B8
    })

    init(mode: LanguageInputMode, rawInput: String, preedit: String,
         candidates: [LanguageConversionCandidate], token: LanguageCompositionToken,
         statusText: String?, height: CGFloat,
         onChoose: @escaping (String, LanguageCompositionToken) -> Void,
         onLiteral: @escaping () -> Void, onClose: @escaping () -> Void,
         onCancel: @escaping () -> Void, queuedPunctuation: String? = nil) {
        self.mode = mode
        self.rawInput = rawInput
        self.preedit = preedit
        self.candidates = candidates
        self.token = token
        self.statusText = statusText
        self.height = height
        self.onChoose = onChoose
        self.onLiteral = onLiteral
        self.onClose = onClose
        self.onCancel = onCancel
        self.queuedPunctuation = queuedPunctuation
    }

    var body: some View {
        ConversionTouchSnapshotView(latest: ConversionDisplaySnapshot(
            mode: mode, rawInput: rawInput, preedit: preedit, candidates: candidates,
            token: token, statusText: statusText, onChoose: onChoose, onLiteral: onLiteral,
            onCancel: onCancel)) { display, touching in
            if display.mode == .koreanTwoSetHangul {
                VStack(spacing: 0) {
                    HStack {
                        Text("Two-Set Hangul").font(.footnote).foregroundStyle(KeyboardCandidateInk.secondary)
                        Spacer()
                        Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("Close Conversion Choices")
                    }.padding(.leading, 12)
                    KoreanHangulWordRow(display: display, touching: touching)
                    Spacer(minLength: 0)
                    ConversionPanelAction(title: "Cancel Conversion", action: display.onCancel, foreground: Self.cancelInk)
                }
                .frame(height: max(0, height))
                .buttonStyle(KeyboardCandidateButtonStyle())
            } else {
                expandedContent(display)
            }
        }
    }

    private func expandedContent(_ display: ConversionDisplaySnapshot) -> some View {
        GeometryReader { geometry in
            let twoColumns = !dynamicTypeSize.isAccessibilitySize && geometry.size.width >= 264
            let columns = Array(repeating: GridItem(.flexible(minimum: 120), spacing: 8), count: twoColumns ? 2 : 1)
            let separatorHeight = 1 / displayScale
            let cancelHeight = cancelActionHeight(width: geometry.size.width)
            // Header, one grid row, literal and Cancel each retain >=44 points.
            // Content ideal heights must never decide whether recovery is pinned.
            let minimumPinnedHeight = 44 * 3 + cancelHeight + separatorHeight
            if geometry.size.height >= minimumPinnedHeight {
                let textRegionBudget = geometry.size.height - cancelHeight - separatorHeight - 44
                let headerHeight = min(min(max(44, geometry.size.height * 0.24), 100), textRegionBudget - 44)
                let literalHeight = min(max(44, geometry.size.height * 0.25), textRegionBudget - headerHeight)
                let gridHeight = geometry.size.height - headerHeight - literalHeight - cancelHeight - separatorHeight
                VStack(spacing: 0) {
                    expandedHeader(display, height: headerHeight)
                    ScrollView { choiceContent(display, columns: columns) }
                        .conversionUnmaskedScrollEdges()
                        .frame(height: gridHeight)
                    KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8)
                    recoveryActions(display, literalHeight: literalHeight, cancelHeight: cancelHeight)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else {
                // Only genuinely short bounds use whole-panel scrolling. Even here
                // the literal scrolls independently and Cancel follows outside it.
                ScrollView {
                    VStack(spacing: 0) {
                        expandedHeader(display, height: 100)
                        choiceContent(display, columns: columns)
                        KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8)
                        recoveryActions(display, literalHeight: max(44, geometry.size.height * 0.25),
                                        cancelHeight: cancelHeight)
                    }
                }
                .conversionUnmaskedScrollEdges()
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(height: max(0, height))
        .clipped()
        .buttonStyle(KeyboardCandidateButtonStyle())
        .foregroundStyle(Color(uiColor: .label))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversion Choices")
        .onAppear {
            focused = display.outputs.first.map { .candidate($0.id) } ?? .preedit
        }
    }

    private func expandedHeader(_ display: ConversionDisplaySnapshot, height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(display.preedit.isEmpty ? display.rawInput : display.preedit).font(.body)
                        .foregroundStyle(KeyboardCandidateInk.secondary)
                    Text(KeyboardConversionShelfMetrics.caption(for: display.mode)).font(.footnote)
                        .foregroundStyle(KeyboardCandidateInk.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .conversionUnmaskedScrollEdges()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unfinished text")
            .accessibilityValue(conversionUnfinishedValue(rawInput: display.rawInput, preedit: display.preedit))
            .accessibilityFocused($focused, equals: .preedit)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Close Conversion Choices")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Keeps unfinished text without inserting it")
            .accessibilityAction { onClose() }
        }
        .padding(.leading, 8)
        .frame(height: height)
    }

    private func choiceContent(_ display: ConversionDisplaySnapshot, columns: [GridItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let queuedPunctuation {
                Text("Then insert \(queuedPunctuation)").font(.footnote)
                    .foregroundStyle(KeyboardCandidateInk.secondary)
            }
            if let statusText = display.statusText {
                Text(statusText).font(.footnote)
                    .foregroundStyle(KeyboardCandidateInk.secondary)
            }
            if display.outputs.isEmpty {
                Text(display.rawInput.isEmpty ? "Type to convert" : "No matching conversion").font(.body)
                    .foregroundStyle(KeyboardCandidateInk.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(display.outputs) { candidate in
                    ConversionCandidateButton(candidate: candidate, token: display.token,
                                              pending: candidate.id == display.outputs.first?.id,
                                              expanded: true, onChoose: display.onChoose)
                        .accessibilityFocused($focused, equals: .candidate(candidate.id))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    private func cancelActionHeight(width: CGFloat) -> CGFloat {
        // Match ConversionPanelAction's scaled body, 12-point horizontal padding,
        // 8-point vertical padding and this panel's 8-point side insets. Measuring
        // wrapped text keeps the explicit short-height threshold valid at AX sizes.
        let bounds = ("Cancel Conversion" as NSString).boundingRect(
            with: CGSize(width: max(1, width - 40), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: cancelSize)], context: nil)
        return max(44, ceil(bounds.height) + 16)
    }

    private func recoveryActions(_ display: ConversionDisplaySnapshot, literalHeight: CGFloat, cancelHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            literalRegion(display, height: literalHeight)
            ConversionPanelAction(title: "Cancel Conversion", action: display.onCancel, foreground: Self.cancelInk)
                .frame(height: cancelHeight)
                .accessibilityHint("Clears unfinished text without deleting text in the app")
        }
        .padding(.horizontal, 8)
    }

    private func literalRegion(_ display: ConversionDisplaySnapshot, height: CGFloat) -> some View {
        // The stable bounded region owns ONE AX button, not either conditional
        // ViewThatFits child. Physical taps still use the same frozen callback.
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                literalButton(rawInput: display.rawInput, action: display.onLiteral)
                ScrollView(.vertical) {
                    literalButton(rawInput: display.rawInput, action: display.onLiteral)
                }
                .conversionUnmaskedScrollEdges()
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Insert exactly as typed: \(display.rawInput)")
        .accessibilityValue(display.rawInput)
        .accessibilityHint("Inserts the exact typed text")
        .accessibilityAddTraits(.isButton)
        .disabled(display.rawInput.isEmpty)
        .accessibilityAction {
            guard !display.rawInput.isEmpty else { return }
            display.onLiteral()
        }
    }

    private func literalButton(rawInput: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: rawInput)
                .font(.system(size: outputSize, weight: .regular))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
    }
}

/// No implicit dismissal, timeout, outside-tap action, or host mutation.
/// The owner supplies context-validated transition actions and bounds this view.
struct KeyboardFinishConversionView: View {
    let rawInput: String
    var confirmsComposedText = false
    let onKeepTypedText: () -> Void
    let onCancelConversion: () -> Void
    let onKeepEditing: () -> Void

    @AccessibilityFocusState private var headerFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Finish Conversion")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headerFocused)
                    Text(rawInput).font(.body)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Unfinished text")
                        .accessibilityValue(rawInput)
                    Text("This unfinished text hasn’t been inserted. Choose what to do before continuing.")
                        .font(.footnote)
                        .foregroundStyle(KeyboardLanguageInformativeInk.secondary)
                    ConversionPanelAction(title: confirmsComposedText ? "Finish Conversion" : "Keep Typed Text", action: onKeepTypedText)
                        .accessibilityValue(rawInput)
                        .accessibilityHint(confirmsComposedText ? "Inserts the composed text, then continues the requested action" : "Inserts the exact typed text, then continues the requested action")
                    ConversionPanelAction(title: "Cancel Conversion", action: onCancelConversion)
                        .accessibilityHint("Clears unfinished text, then continues the requested action")
                    ConversionPanelAction(title: "Keep Editing", action: onKeepEditing)
                        .accessibilityHint("Keeps unfinished text and abandons the requested action")
                }
                .padding(8)
            }
            .conversionUnmaskedScrollEdges()
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .foregroundStyle(Color(uiColor: .label))
        .onAppear { headerFocused = true }
    }
}

private struct ConversionCandidateButton: View {
    let candidate: LanguageConversionCandidate
    let token: LanguageCompositionToken
    let pending: Bool
    let expanded: Bool
    let onChoose: (String, LanguageCompositionToken) -> Void

    var body: some View {
        Button { [candidate, token, onChoose] in
            onChoose(candidate.id, token)
        } label: {
            KeyboardCandidateText(output: candidate.output, pending: pending, expanded: expanded)
                .overlay(alignment: .bottom) {
                    if expanded {
                        KeyboardCandidateDivider(vertical: false).padding(.horizontal, 8)
                    }
                }
        }
        .buttonStyle(KeyboardCandidateButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Insert \(candidate.output)")
        .accessibilityValue([annotation, pending ? "Pending" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(pending ? .isSelected : [])
    }

    private var annotation: String? {
        switch candidate.source {
        case .hiragana: return "Hiragana"
        case .katakana: return "Katakana"
        case .custom: return "My Words"
        case .engine, .literal: return nil
        }
    }
}

private struct ConversionPanelAction: View {
    let title: String
    let action: () -> Void
    var foreground = Color(uiColor: .systemBlue)

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }
}

private func conversionLiteralName(_ mode: LanguageInputMode) -> String {
    mode == .japaneseRomaji ? "Keep Roman Letters" : "Keep Typed Text"
}

private func conversionUnfinishedValue(rawInput: String, preedit: String) -> String {
    guard !rawInput.isEmpty else { return "No unfinished text" }
    guard !preedit.isEmpty, !preedit.utf8.elementsEqual(rawInput.utf8) else { return rawInput }
    return "\(preedit), typed text: \(rawInput)"
}

// Conversion text and 44-point choice/recovery targets must remain readable all
// the way to each scroll boundary, rather than under iOS 26's automatic blur.
// Keep this file-local name distinct from the controller's private helper.
private extension View {
    @ViewBuilder func conversionUnmaskedScrollEdges() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectHidden() }
        else { self }
    }
}
