#if canImport(UIKit)
import UIKit

@MainActor
struct KeyboardVariantActions {
    let isCurrent: () -> Bool
    let insert: (String) -> Bool
    var inspect: ((String) -> Bool)? = nil
    var edit: (() -> Bool)? = nil
    var hold: (() -> Bool)? = nil
    var options: [String]? = nil
    var longPressOptions: [String]? = nil
    var swipeUp: [String]? = nil
    var swipeDown: [String]? = nil
    var tap: (() -> Bool)? = nil
    var insertGesture: ((String, KeyboardKeySettings.Gesture) -> Bool)? = nil
    var repeatOnHold: (() -> Bool)? = nil
}

/// The callbacks and exact choices belong to one physical press. A rendered
/// update never redirects an existing hold to a different key or document.
@MainActor
final class KeyboardVariantInteraction {
    typealias Factory = () -> KeyboardVariantActions?
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Timer
    var show: (([String], Bool, Bool) -> Bool)?
    var hide: (() -> Void)?
    var highlight: ((Int?) -> Void)?
    var activityChanged: ((Bool) -> Void)?
    var physicalContextIsCurrent: (() -> Bool)?
    private(set) var token: UUID?
    private(set) var popupVisible = false
    private(set) var swipeSelecting = false
    private var configuration: (UUID, String, [[UInt16]], Bool)?
    private var factory: Factory?
    private var text = ""
    private var options: [String] = []
    private var pressOptions: [String] = []
    private var actions: KeyboardVariantActions?
    private var selected: Int?
    private var inspectedIndex = 0
    private var swipeOriginX: CGFloat = 0
    private var swipeHasLateralIntent = false
    private var popupAllowsCommands = true
    private var tapText = ""
    private var activeGesture: KeyboardKeySettings.Gesture?
    private var repeating = false
    private var repeatDeliveryID: UUID?
    private var timer: Timer?
    private var tracking = false
    var hasPhysicalPress: Bool { tracking && token != nil }
    private var generation = UUID()
    private weak var owner: AnyObject?
    private let schedule: Scheduler

    init(schedule: @escaping Scheduler = { interval, action in
        let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }) { self.schedule = schedule }
    deinit { timer?.invalidate() }

    func configure(context: UUID, key: String, text: String, variants: [String], enabled: Bool,
                   preservesPressAcrossTextChanges: Bool = false,
                   factory: @escaping Factory) {
        let values = KeyboardVariantPolicy.options(text: text, variants: variants)
        let exact = values.map { Array($0.utf16) }
        if let old = configuration,
           old.0 != context || old.1 != key || (!preservesPressAcrossTextChanges && old.2 != exact) || old.3 != enabled {
            cancel(ending: false)
        }
        configuration = (context, key, exact, enabled)
        self.factory = factory
        self.text = text
        options = values
    }

    @discardableResult
    func begin(owner: AnyObject) -> Bool {
        guard !tracking, configuration?.3 == true, !options.isEmpty, let factory else { return false }
        tracking = true
        self.owner = owner
        let id = UUID()
        token = id
        generation = id
        let captured = factory()
        guard token == id, self.owner === owner, let captured else { return false }
        let current = captured.isCurrent()
        guard token == id, self.owner === owner, current else { return false }
        guard validatePhysicalContext(id: id) else { return false }
        let choices = captured.options.flatMap { values in
            values.first.map { KeyboardVariantPolicy.options(text: $0, variants: Array(values.dropFirst())) }
        } ?? options
        guard !choices.isEmpty else { return false }
        actions = captured
        pressOptions = choices
        tapText = choices[0]
        selected = 0
        inspectedIndex = 0
        activityChanged?(true)
        guard token == id else { return false }
        let hasHold = captured.longPressOptions.map { !KeyboardVariantPolicy.candidates(override: $0, defaults: []).isEmpty }
            ?? (choices.count > 1 || captured.inspect != nil || captured.edit != nil || captured.hold != nil || captured.repeatOnHold != nil)
        if hasHold {
            timer = schedule(0.4) { [weak self, weak owner] in
                guard let self, self.token == id else { return }
                guard let owner else { self.cancel(); return }
                guard self.owner === owner else { return }
                self.held(id: id)
            }
        }
        return true
    }

    private func held(id: UUID) {
        guard token == id, tracking, !swipeSelecting, !repeating, activeGesture == nil, let actions else { return }
        let current = actions.isCurrent()
        guard token == id else { return }
        guard current else { cancel(ending: false); return }
        guard validatePhysicalContext(id: id) else { return }
        timer?.invalidate(); timer = nil
        if actions.longPressOptions == nil, actions.repeatOnHold != nil {
            repeating = true
            repeatTick(id: id)
            return
        }
        if actions.longPressOptions == nil, let hold = actions.hold {
            let terminal = cancel(ending: true)
            guard generation == terminal, token == nil, !tracking else { return }
            _ = hold()
            return
        }
        if let custom = actions.longPressOptions {
            pressOptions = KeyboardVariantPolicy.candidates(override: custom, defaults: [])
            popupAllowsCommands = false
        }
        guard !pressOptions.isEmpty else { cancel(ending: false); return }
        activeGesture = .longPress
        openPopup(id: id)
    }

    private func repeatTick(id: UUID) {
        guard token == id, repeating, let actions else { return }
        guard tracking, owner != nil else { cancel(); return }
        let current = actions.isCurrent()
        guard token == id else { return }
        guard current else { cancel(ending: false); return }
        guard validatePhysicalContext(id: id) else { return }
        let accepted = actions.repeatOnHold?() ?? false
        guard token == id else { return }
        guard accepted else { cancel(ending: false); return }
        let delivery = UUID()
        repeatDeliveryID = delivery
        timer = schedule(0.085) { [weak self] in
            guard let self, self.repeatDeliveryID == delivery else { return }
            self.repeatDeliveryID = nil
            self.repeatTick(id: id)
        }
    }

    private func openPopup(id: UUID) {
        guard token == id, let actions, !popupVisible else { return }
        popupVisible = true
        guard show?(pressOptions, popupAllowsCommands && actions.inspect != nil,
                    popupAllowsCommands && actions.edit != nil) == true else {
            if token == id { cancel(ending: false) }
            return
        }
        guard token == id else { return }
        highlight?(0)
    }

    private func validatePhysicalContext(id: UUID) -> Bool {
        guard token == id else { return false }
        let current = physicalContextIsCurrent?() ?? true
        guard token == id else { return false }
        guard current else { cancel(); return false }
        return true
    }

    /// A swipe picks its group before any choices appear. Once a hold or a
    /// swipe shows its choices, the press keeps that group: vertical motion
    /// never switches to another one, and sideways motion selects within it.
    private func gestureDirection(at delta: CGPoint) -> KeyboardKeySettings.Gesture? {
        popupVisible ? nil : KeyboardVariantPolicy.swipeDirection(delta: delta)
    }

    func move(owner: AnyObject, index: Int?, movedBeforeHold: Bool, delta: CGPoint? = nil, directPopupIndex: Int? = nil) {
        guard tracking, self.owner === owner, let id = token, let actions else { return }
        let current = actions.isCurrent()
        guard token == id else { return }
        guard current else { cancel(ending: false); return }
        guard validatePhysicalContext(id: id) else { return }
        if let delta, !delta.x.isFinite || !delta.y.isFinite { cancel(ending: false); return }
        if repeating {
            if movedBeforeHold { cancel(ending: false) }
            return
        }
        if let delta, let direction = gestureDirection(at: delta) {
            let configured = direction == .swipeUp ? actions.swipeUp : actions.swipeDown
            let choices = configured.map { KeyboardVariantPolicy.candidates(override: $0, defaults: []) } ?? []
            guard !choices.isEmpty else { cancel(ending: false); return }
            timer?.invalidate(); timer = nil
            pressOptions = choices
            popupAllowsCommands = false
            swipeSelecting = true
            activeGesture = direction
            swipeOriginX = delta.x
            swipeHasLateralIntent = false
            selected = 0
            inspectedIndex = 0
            openPopup(id: id)
            return
        }
        guard token == id else { return }
        if swipeSelecting {
            // A vertical flick may cross the popup by accident. Direct cells
            // become selectable only after deliberate sideways motion. Keep
            // that intent so wrapped rows remain reachable on narrow screens.
            guard let delta else { cancel(ending: false); return }
            let horizontal = delta.x - swipeOriginX
            guard horizontal.isFinite else { cancel(ending: false); return }
            if abs(horizontal) >= KeyboardVariantPolicy.horizontalChoiceStride / 2 { swipeHasLateralIntent = true }
            let direct = swipeHasLateralIntent ? directPopupIndex : nil
            let value = direct.flatMap { pressOptions.indices.contains($0) ? $0 : nil }
                ?? KeyboardVariantPolicy.horizontalChoice(deltaX: horizontal, count: pressOptions.count)
            guard let value else {
                cancel(ending: false); return
            }
            if selected != value { selected = value; highlight?(value) }
            return
        }
        if !popupVisible {
            if let delta, abs(delta.y) > abs(delta.x), abs(delta.y) < KeyboardVariantPolicy.swipeThreshold,
               (delta.y < 0 ? actions.swipeUp : actions.swipeDown) != nil { return }
            if movedBeforeHold { cancel(ending: false) }
            return
        }
        let count = pressOptions.count + (popupAllowsCommands && actions.inspect != nil ? 1 : 0) + (popupAllowsCommands && actions.edit != nil ? 1 : 0)
        let value = index.flatMap { (0..<count).contains($0) ? $0 : nil }
        if let value, value < pressOptions.count { inspectedIndex = value }
        if selected != value { selected = value; highlight?(value) }
    }

    @discardableResult
    func end(owner: AnyObject, inside: Bool) -> Bool {
        guard tracking, self.owner === owner else { return false }
        if let id = token, !validatePhysicalContext(id: id) { return false }
        let captured = actions
        let selected = selected
        let choices = pressOptions
        let wasPopup = popupVisible
        let inspectChoice = inspectedIndex
        let allowsCommands = popupAllowsCommands
        let original = tapText
        let gesture = activeGesture
        let wasRepeating = repeating
        let valid = token != nil && inside
        let terminalGeneration = cancel(ending: true)
        guard valid, generation == terminalGeneration, token == nil, !tracking, let captured, let selected else { return false }
        let current = captured.isCurrent()
        guard current, generation == terminalGeneration, token == nil, !tracking else { return false }
        if wasRepeating { return true }
        if !wasPopup { return captured.tap?() ?? captured.insert(original) }
        if allowsCommands, selected == choices.count, let inspect = captured.inspect {
            return inspect(choices[inspectChoice])
        }
        if allowsCommands, selected == choices.count + (captured.inspect == nil ? 0 : 1), let edit = captured.edit {
            return edit()
        }
        guard choices.indices.contains(selected) else { return false }
        if let gesture, let insert = captured.insertGesture { return insert(choices[selected], gesture) }
        return captured.insert(choices[selected])
    }

    @discardableResult
    func cancel(ending: Bool = true) -> UUID {
        timer?.invalidate(); timer = nil
        token = nil
        generation = UUID()
        let cancelledGeneration = generation
        actions = nil
        pressOptions = []
        selected = nil
        let wasVisible = popupVisible
        popupVisible = false
        swipeSelecting = false
        swipeOriginX = 0
        swipeHasLateralIntent = false
        popupAllowsCommands = true
        tapText = ""
        activeGesture = nil
        repeating = false
        repeatDeliveryID = nil
        if ending { tracking = false; owner = nil }
        if wasVisible { hide?() }
        if token == nil { activityChanged?(false) }
        return cancelledGeneration
    }

    func activate(text: String? = nil, inspect: Bool = false) -> Bool {
        guard let captured = freshAccessibilityActions() else { return false }
        if text == nil, !inspect, let tap = captured.tap { return tap() }
        let choices = captured.options.map { KeyboardVariantPolicy.candidates(override: nil, defaults: $0) } ?? options
        let chosen = text ?? choices.first ?? self.text
        guard KeyboardVariantPolicy.contains(chosen, in: choices) else { return false }
        if inspect { return captured.inspect?(chosen) ?? false }
        return captured.insert(chosen)
    }

    func activateEdit() -> Bool {
        guard let captured = freshAccessibilityActions() else { return false }
        return captured.edit?() ?? false
    }
    func activateHold() -> Bool {
        guard let captured = freshAccessibilityActions() else { return false }
        return captured.hold?() ?? false
    }
    func activateGesture(_ gesture: KeyboardKeySettings.Gesture, text: String? = nil) -> Bool {
        guard let captured = freshAccessibilityActions() else { return false }
        let values: [String]?
        switch gesture {
        case .tap, .shiftedTap: return false
        case .longPress: values = captured.longPressOptions ?? captured.options ?? options
        case .swipeUp: values = captured.swipeUp
        case .swipeDown: values = captured.swipeDown
        }
        guard let values else { return false }
        let choices = gesture == .longPress && captured.longPressOptions == nil
            ? KeyboardVariantPolicy.candidates(override: nil, defaults: values)
            : KeyboardVariantPolicy.candidates(override: values, defaults: [])
        guard let chosen = text ?? choices.first,
              KeyboardVariantPolicy.contains(chosen, in: choices) else { return false }
        return captured.insertGesture?(chosen, gesture) ?? captured.insert(chosen)
    }
    private func freshAccessibilityActions() -> KeyboardVariantActions? {
        let cancelledGeneration = cancel()
        guard generation == cancelledGeneration, !tracking, token == nil, configuration?.3 == true, let factory else { return nil }
        let id = UUID()
        token = id
        let captured = factory()
        guard token == id else { return nil }
        guard let captured else { token = nil; return nil }
        let current = captured.isCurrent()
        guard token == id else { return nil }
        token = nil
        return current ? captured : nil
    }
}

/// Owns the real UIKit touch stream; the popup never takes first responder and
/// never allocates space outside the containing custom keyboard input view.
@MainActor
final class KeyboardVariantButton: UIControl {
    private let title = UILabel()
    private let secondaryTitle = UILabel()
    private let image = UIImageView()
    let interaction: KeyboardVariantInteraction
    private let hover = KeyboardInspectableInteraction()
    private var activeIDs: Set<ObjectIdentifier> = []
    private weak var primary: UITouch?
    private var initialPoint = CGPoint.zero
    private weak var capturedWindow: UIWindow?
    private weak var capturedContainer: UIView?
    private var capturedWindowBounds = CGRect.zero
    private var capturedWindowFrame = CGRect.zero
    private var capturedContainerBounds = CGRect.zero
    private var popup: UIView?
    private var popupLayout: KeyboardVariantPopupLayout?
    private var popupLabels: [UILabel] = []
    private var originalRect = CGRect.zero
    private var currentOptions: [String] = []
    private var configuredFont: UIFont = .systemFont(ofSize: 23)
    private var contentPosition: KeyboardKeyContentPosition = .center
    private var popupFont: ((String) -> UIFont)?
    private var displayText: (String) -> String = { $0 }
    private lazy var holdArbitration = UILongPressGestureRecognizer(target: self, action: #selector(arbitrateHold(_:)))

    init(interaction suppliedInteraction: KeyboardVariantInteraction? = nil) {
        let interaction = suppliedInteraction ?? KeyboardVariantInteraction()
        self.interaction = interaction
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.02)
        isAccessibilityElement = true
        accessibilityTraits = .button
        title.textAlignment = .center
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.5
        title.isUserInteractionEnabled = false
        image.contentMode = .center
        image.isUserInteractionEnabled = false
        secondaryTitle.textAlignment = .center
        secondaryTitle.font = .systemFont(ofSize: 12)
        secondaryTitle.textColor = .secondaryLabel
        secondaryTitle.adjustsFontSizeToFitWidth = true
        secondaryTitle.minimumScaleFactor = 0.7
        secondaryTitle.isUserInteractionEnabled = false
        secondaryTitle.isAccessibilityElement = false
        secondaryTitle.isHidden = true
        addSubview(title); addSubview(image); addSubview(secondaryTitle)
        interaction.show = { [weak self] values, inspect, edit in self?.showPopup(values, inspect: inspect, edit: edit) ?? false }
        interaction.hide = { [weak self] in self?.removePopup() }
        interaction.highlight = { [weak self] index in self?.highlight(index) }
        interaction.activityChanged = { [weak self] active in self?.isHighlighted = active }
        interaction.physicalContextIsCurrent = { [weak self] in self?.geometryIsCurrent == true }
        // Recognition prevents an ancestor scroll pan from taking a choice
        // slide after the hold; raw touches remain the sole insertion owner.
        holdArbitration.minimumPressDuration = 0.4
        holdArbitration.allowableMovement = 10
        holdArbitration.cancelsTouchesInView = false
        holdArbitration.delaysTouchesBegan = false
        holdArbitration.delaysTouchesEnded = false
        addGestureRecognizer(holdArbitration)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: KeyboardTypingLayoutPolicy.regularKeyHeight) }
    private(set) lazy var pressFeedback = KeyboardTouchFeedback.attach(to: self)
    override var isHighlighted: Bool {
        didSet { pressFeedback.setPressed(isHighlighted) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        title.frame = bounds.insetBy(dx: 3, dy: 2)
        if !secondaryTitle.isHidden {
            let compact = bounds.height < 44
            let size: CGFloat = compact ? 9 : 12
            secondaryTitle.font = secondaryTitle.text.flatMap { popupFont?($0) }?.withSize(size) ?? .systemFont(ofSize: size)
            secondaryTitle.frame = CGRect(x: 3, y: compact ? 1 : 3, width: max(0, bounds.width - 6), height: compact ? 10 : 15)
            title.frame = CGRect(x: 3, y: compact ? 11 : 17, width: max(0, bounds.width - 6), height: max(0, bounds.height - (compact ? 12 : 19)))
        }
        image.frame = contentPosition.alignedRect(CGRect(origin: .zero, size: image.image?.size ?? bounds.size), in: bounds)
        if contentPosition == .center { image.frame = bounds }
        if interaction.hasPhysicalPress, !geometryIsCurrent { interaction.cancel() }
    }

    func configure(context: UUID, key: String, text: String, variants: [String], enabled: Bool,
                   font: UIFont, symbol: String? = nil, foreground: UIColor = .label,
                   preservesPressAcrossTextChanges: Bool = false,
                   longPressOptions: [String]? = nil, swipeUp: [String]? = nil, swipeDown: [String]? = nil,
                   secondaryText: String? = nil,
                   contentPosition: KeyboardKeyContentPosition = .center,
                   showsInspection: Bool = false, showsEditing: Bool = false, holdLabel: String? = nil,
                   popupFont: ((String) -> UIFont)? = nil,
                   displayText: @escaping (String) -> String = { $0 },
                   actionName: ((String) -> String)? = nil,
                   factory: @escaping KeyboardVariantInteraction.Factory) {
        let oldToken = interaction.token
        interaction.configure(context: context, key: key, text: text, variants: variants, enabled: enabled,
            preservesPressAcrossTextChanges: preservesPressAcrossTextChanges, factory: factory)
        if oldToken != nil, interaction.token == nil { holdArbitration.isEnabled = false }
        holdArbitration.isEnabled = enabled
        hover.configure(contextIdentifier: context, itemIdentifier: key, enabled: enabled && showsInspection) {
            guard let actions = factory() else { return nil }
            return .init(insert: { actions.isCurrent() && actions.insert(text) },
                         inspect: { actions.isCurrent() && (actions.inspect?(text) ?? false) })
        }
        isUserInteractionEnabled = enabled
        isAccessibilityElement = enabled
        accessibilityElementsHidden = !enabled
        self.displayText = displayText
        self.contentPosition = contentPosition
        secondaryTitle.text = secondaryText
        secondaryTitle.isHidden = secondaryText?.isEmpty != false || symbol != nil
        setNeedsLayout()
        title.text = displayText(text)
        title.isHidden = symbol != nil
        title.font = font
        title.textColor = foreground
        image.image = symbol.flatMap { UIImage(systemName: $0) }
        image.tintColor = foreground
        image.isHidden = symbol == nil
        configuredFont = font
        self.popupFont = popupFont
        currentOptions = KeyboardVariantPolicy.options(text: text, variants: variants)
        let longChoices = longPressOptions.map { KeyboardVariantPolicy.candidates(override: $0, defaults: []) }
            ?? Array(currentOptions.dropFirst())
        accessibilityCustomActions = longChoices.map { value in
            let points = value.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
            return UIAccessibilityCustomAction(name: actionName?(value) ?? "\(displayText(value)), \(points)") { [weak self] _ in self?.interaction.activateGesture(.longPress, text: value) ?? false }
        }
        let swipeActions: [(KeyboardKeySettings.Gesture, [String]?)] = [(.swipeUp, swipeUp), (.swipeDown, swipeDown)]
        for (gesture, values) in swipeActions {
            for value in KeyboardVariantPolicy.candidates(override: values, defaults: []) {
                let points = value.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: "\(gesture == .swipeUp ? "Swipe up" : "Swipe down"): \(displayText(value)), \(points)") { [weak self] _ in
                    self?.interaction.activateGesture(gesture, text: value) ?? false
                })
            }
        }
        if showsInspection {
            accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: "Inspect Unicode properties") { [weak self] _ in
                self?.interaction.activate(inspect: true) ?? false
            })
        }
        if showsEditing {
            accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: "Edit variants") { [weak self] _ in
                self?.interaction.activateEdit() ?? false
            })
        }
        if let holdLabel, longPressOptions == nil {
            accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: holdLabel) { [weak self] _ in
                self?.interaction.activateHold() ?? false
            })
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = activeIDs.isEmpty
        activeIDs.formUnion(touches.map(ObjectIdentifier.init))
        guard wasEmpty, activeIDs.count == 1, touches.count == 1, let touch = touches.first,
              window != nil else { cancelForAdditionalTouch(); return }
        primary = touch
        _ = beginPhysicalPress(owner: touch, point: touch.location(in: self))
    }
    @discardableResult
    func beginPhysicalPress(owner: AnyObject, point: CGPoint) -> Bool {
        guard point.x.isFinite, point.y.isFinite, let window, let container = inputContainer else { return false }
        capturedWindow = window
        capturedContainer = container
        capturedWindowBounds = window.bounds
        capturedWindowFrame = window.frame
        capturedContainerBounds = container.bounds
        initialPoint = point
        originalRect = convert(bounds, to: container)
        hover.endHover()
        return interaction.begin(owner: owner)
    }
    func cancelForAdditionalTouch() {
        interaction.cancel(); hover.cancelAll()
        holdArbitration.isEnabled = false
        holdArbitration.isEnabled = isUserInteractionEnabled
    }
    static func cancelInteractions(in root: UIView) {
        var pending = [root]
        while let view = pending.popLast() {
            pending.append(contentsOf: view.subviews)
            guard let key = view as? KeyboardVariantButton else { continue }
            key.interaction.cancel()
            key.hover.cancelAll()
            key.activeIDs.removeAll()
            key.primary = nil
            key.clearGeometry()
            key.holdArbitration.isEnabled = false
            key.holdArbitration.isEnabled = key.isUserInteractionEnabled
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let primary, touches.contains(where: { $0 === primary }) else { return }
        guard geometryIsCurrent else { interaction.cancel(); return }
        let local = primary.location(in: self)
        let point = primary.location(in: capturedContainer)
        let index = selectedIndex(at: point)
        interaction.move(owner: primary, index: index,
            movedBeforeHold: abs(local.x - initialPoint.x) > 10 || abs(local.y - initialPoint.y) > 10,
            delta: CGPoint(x: local.x - initialPoint.x, y: local.y - initialPoint.y),
            directPopupIndex: directPopupIndex(at: point))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { activeIDs.remove(ObjectIdentifier(touch)) }
        guard let primary, touches.contains(where: { $0 === primary }) else { return }
        if geometryIsCurrent {
            let local = primary.location(in: self)
            let point = primary.location(in: capturedContainer)
            let index = selectedIndex(at: point)
            interaction.move(owner: primary, index: index, movedBeforeHold: false,
                delta: CGPoint(x: local.x - initialPoint.x, y: local.y - initialPoint.y),
                directPopupIndex: directPopupIndex(at: point))
            let inside = interaction.swipeSelecting ? capturedContainer.map { contains(point, in: $0.bounds) } == true
                : interaction.popupVisible ? index != nil : contains(local, in: bounds)
            _ = interaction.end(owner: primary, inside: inside)
        } else { interaction.cancel() }
        self.primary = nil
        if activeIDs.isEmpty { clearGeometry() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { activeIDs.remove(ObjectIdentifier(touch)) }
        interaction.cancel(); hover.endHover(); primary = nil
        if activeIDs.isEmpty { clearGeometry() }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window {
            interaction.cancel(); hover.cancelAll(); activeIDs.removeAll(); primary = nil; clearGeometry()
        }
        super.willMove(toWindow: newWindow)
    }
    override func accessibilityActivate() -> Bool { interaction.activate() }
    @objc private func arbitrateHold(_ gesture: UILongPressGestureRecognizer) {
        // Deliberately no insert/inspect action: the captured raw-touch state
        // owns the timer, highlighted choice and the sole terminal callback.
    }
    @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state { case .began: hover.beginHover(); case .ended, .cancelled, .failed: hover.endHover(); default: break }
    }
    private var inputContainer: UIView? {
        var current = superview
        while let candidate = current {
            if candidate is UIInputView { return candidate }
            current = candidate.superview
        }
        return nil
    }
    private var geometryIsCurrent: Bool {
        guard let capturedWindow, let capturedContainer, window === capturedWindow,
              inputContainer === capturedContainer else { return false }
        return same(capturedWindow.bounds, capturedWindowBounds) && same(capturedWindow.frame, capturedWindowFrame)
            && same(capturedContainer.bounds, capturedContainerBounds)
            && same(convert(bounds, to: capturedContainer), originalRect)
    }
    private func clearGeometry() { capturedWindow = nil; capturedContainer = nil; removePopup() }
    private func same(_ a: CGRect, _ b: CGRect) -> Bool {
        a.origin.x == b.origin.x && a.origin.y == b.origin.y && a.width == b.width && a.height == b.height
    }
    private func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x.isFinite && point.y.isFinite && point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }
    func selectedIndex(at point: CGPoint) -> Int? {
        guard interaction.popupVisible, let popupLayout else { return contains(point, in: originalRect) ? 0 : nil }
        if contains(point, in: originalRect) { return 0 }
        return popupLayout.index(at: CGPoint(x: point.x - popupLayout.frame.minX, y: point.y - popupLayout.frame.minY))
    }
    private func directPopupIndex(at point: CGPoint) -> Int? {
        guard let popupLayout, contains(point, in: popupLayout.frame) else { return nil }
        return popupLayout.index(at: CGPoint(x: point.x - popupLayout.frame.minX, y: point.y - popupLayout.frame.minY))
    }
    private func showPopup(_ values: [String], inspect: Bool, edit: Bool) -> Bool {
        guard geometryIsCurrent, let capturedContainer,
              let layout = KeyboardVariantPopupLayout(anchor: originalRect, container: capturedContainer.bounds,
                  count: values.count + (inspect ? 1 : 0) + (edit ? 1 : 0), choiceCount: values.count) else { return false }
        let popup = UIView(frame: layout.frame)
        popup.backgroundColor = .secondarySystemBackground
        popup.layer.cornerRadius = 10
        popup.layer.borderWidth = 0.5
        popup.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        popup.layer.shadowOpacity = 0.16
        popup.layer.shadowRadius = 5
        popup.isUserInteractionEnabled = false
        popup.accessibilityIdentifier = "keyboard.variants"
        popupLabels = layout.cells.enumerated().map { index, frame in
            let label = UILabel(frame: frame.insetBy(dx: 2, dy: 2))
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.35
            label.layer.cornerRadius = 7
            label.clipsToBounds = true
            label.text = index < values.count ? displayText(values[index]) : (inspect && index == values.count ? "Inspect" : "Edit")
            label.font = index < values.count ? (popupFont?(values[index]) ?? configuredFont) : .systemFont(ofSize: 12)
            label.accessibilityIdentifier = "keyboard.variant.\(index)"
            popup.addSubview(label)
            return label
        }
        popupLayout = layout
        self.popup = popup
        capturedContainer.addSubview(popup)
        return true
    }
    private func removePopup() { popup?.removeFromSuperview(); popup = nil; popupLayout = nil; popupLabels = [] }
    private func highlight(_ index: Int?) {
        for (offset, label) in popupLabels.enumerated() {
            label.backgroundColor = offset == index ? tintColor : .clear
            label.textColor = offset == index ? .white : .label
        }
    }
}
#endif
