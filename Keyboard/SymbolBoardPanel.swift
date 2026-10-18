import SwiftUI
import UIKit

struct SymbolBoardSaveTargetPanel: View {
    @ObservedObject var store: SymbolBoardStore
    let text: String
    let guardFactory: () -> (() -> Bool)?
    let sessionGuardFactory: () -> (() -> Bool)?
    let close: () -> Void
    @State private var sessionIsCurrent: (() -> Bool)?
    @State private var failed = false
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Save to symbol board").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel", action: close).accessibilityIdentifier("keyboard.boards.save.cancel")
            }
            .frame(height: 36)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("keyboard.boards.save.header")
            Text(symbolBoardPreview(text)).font(.system(size: 28)).lineLimit(1)
                .minimumScaleFactor(0.5).frame(height: 36)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.boards) { board in
                        Button {
                            guard sessionIsCurrent?() == true,
                                  store.boards.contains(where: { $0.id == board.id }) else { failed = true; return }
                            if store.add(text: text, to: board.id) != nil { close() }
                            else { failed = true }
                        } label: {
                            HStack { Text(board.name); Spacer(); if board.keys.contains(where: { SymbolBoardKey.exact($0.text, text) }) { Image(systemName: "checkmark") } }
                                .padding(.horizontal, 10).frame(minHeight: 36)
                        }.accessibilityIdentifier("keyboard.boards.save.\(board.id)")
                    }
                    if let issue = store.loadIssue { Text(issue.rawValue).font(.system(size: 11)) }
                    if failed { Text("This item could not be saved. The input context or board may have changed.").font(.system(size: 11)).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .font(.system(size: 13))
        .buttonStyle(SymbolBoardConfigurationButtonStyle(guardFactory: guardFactory))
        .symbolBoardOpaquePanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard.boards.saveTarget")
        .onAppear { sessionIsCurrent = sessionGuardFactory() }
    }
}

/// Configuration stays inside the extension's existing input view. The local
/// pad never becomes first responder and never forwards its text to the host.
struct SymbolBoardManagerPanel: View {
    @ObservedObject var store: SymbolBoardStore
    let guardFactory: () -> (() -> Bool)?
    let sessionGuardFactory: () -> (() -> Bool)?
    let pick: (SymbolBoardPickerTarget) -> Void
    let close: () -> Void
    var initialKeyID: String? = nil
    @State private var sessionIsCurrent: (() -> Bool)?
    @State private var editingBoardID: String?
    @State private var editingKeyID: String?
    @State private var entryPurpose: EntryPurpose?
    @State private var entry = ""
    @State private var uppercase = false
    @State private var error: String?

    private enum EntryPurpose { case create, rename(String), variant(String, String) }
    private var board: SymbolBoard? { store.boards.first { $0.id == editingBoardID } }
    private var key: SymbolBoardKey? {
        guard let editingBoardID, let editingKeyID else { return nil }
        return store.key(boardID: editingBoardID, keyID: editingKeyID)
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if editingBoardID != nil || entryPurpose != nil {
                    Button("Back") { entryPurpose = nil; entry = ""; if editingKeyID != nil { editingKeyID = nil } else { editingBoardID = nil } }
                        .frame(minWidth: 44)
                        .accessibilityIdentifier("keyboard.boards.back")
                }
                Text("Symbol boards").font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                Button("Done", action: close).frame(minWidth: 44).accessibilityIdentifier("keyboard.boards.close")
            }
            .font(.system(size: 12, weight: .medium)).frame(height: 36)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("keyboard.boards.header")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let issue = store.loadIssue { Text(issue.rawValue).font(.system(size: 12)).accessibilityIdentifier("keyboard.boards.storageIssue") }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).accessibilityIdentifier("keyboard.boards.error") }
                    if entryPurpose != nil { entryPanel }
                    else if let board, let key { keyPanel(board, key) }
                    else if let board { boardPanel(board) }
                    else { boardList }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityIdentifier("keyboard.boards.scroll")
        }
        .font(.system(size: 13))
        .buttonStyle(SymbolBoardConfigurationButtonStyle(guardFactory: guardFactory))
        .symbolBoardOpaquePanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard.boards.manager")
        .onAppear {
            sessionIsCurrent = sessionGuardFactory()
            if let initialKeyID, store.key(boardID: store.activeBoardID, keyID: initialKeyID) != nil {
                editingBoardID = store.activeBoardID; editingKeyID = initialKeyID
            }
        }
    }
    private func act(_ action: () -> Bool) {
        guard sessionIsCurrent?() == true else { error = "The input context changed. Close and reopen symbol boards."; return }
        error = action() ? nil : "This change could not be saved. Check the item and storage limits."
    }
    private func begin(_ purpose: EntryPurpose, value: String = "") {
        guard sessionIsCurrent?() == true else { return }
        entryPurpose = purpose; entry = value; error = nil; uppercase = false
    }
    private var boardList: some View {
        VStack(spacing: 8) {
            ForEach(store.boards) { board in
                HStack(spacing: 6) {
                    Button {
                        act { store.selectBoard(board.id) }
                        if store.activeBoardID == board.id && error == nil { close() }
                    } label: {
                        HStack {
                            Text(board.name).lineLimit(1)
                            if store.preferredStarBoardID == board.id {
                                Text("Star default").font(.system(size: 10, weight: .medium)).fixedSize()
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("keyboard.boards.default.\(board.id)")
                            }
                            Spacer()
                            if store.activeBoardID == board.id { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityIdentifier("keyboard.boards.select.\(board.id)")
                    .accessibilityValue(store.activeBoardID == board.id ? "Selected" : "")
                    Button { act { store.setPreferredStarBoard(board.id) } } label: {
                        Image(systemName: store.preferredStarBoardID == board.id ? "star.fill" : "star")
                    }
                    .accessibilityLabel("Use \(board.name) for the star key")
                    .accessibilityValue(store.preferredStarBoardID == board.id ? "Star default" : "")
                    .accessibilityIdentifier("keyboard.boards.makeDefault.\(board.id)")
                    .disabled(!store.canEdit || store.preferredStarBoardID == board.id)
                    Button("Edit") { editingBoardID = board.id; error = nil }
                        .accessibilityIdentifier("keyboard.boards.edit.\(board.id)")
                }.font(.system(size: 13)).padding(.horizontal, 8).frame(minHeight: 36)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Button("New board") { begin(.create) }.accessibilityIdentifier("keyboard.boards.create")
                .disabled(!store.canEdit || store.boards.count >= SymbolBoardStore.maximumBoards)
            Text("Tap a board to switch now. Its star sets the star-key default. Boards stay on this keyboard.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func boardPanel(_ board: SymbolBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(board.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                Button("Rename") { begin(.rename(board.id), value: board.name) }.accessibilityIdentifier("keyboard.boards.rename")
                Button("Move up") { act { store.moveBoard(board.id, by: -1) } }.accessibilityIdentifier("keyboard.boards.moveUp")
                Button("Move down") { act { store.moveBoard(board.id, by: 1) } }.accessibilityIdentifier("keyboard.boards.moveDown")
            }.font(.system(size: 11))
            Button("Add from Unicode") {
                guard sessionIsCurrent?() == true, store.boards.contains(where: { $0.id == board.id }) else { return }
                pick(.init(boardID: board.id, keyID: nil))
            }.accessibilityIdentifier("keyboard.boards.addKey")
            ForEach(board.keys) { key in
                HStack {
                    Text(symbolBoardPreview(key.text)).font(.system(size: 22)).lineLimit(1)
                        .minimumScaleFactor(0.5).frame(width: 44, height: 36)
                    Text("\(key.variants.count) variants").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") { editingKeyID = key.id; error = nil }
                        .accessibilityIdentifier("keyboard.boards.key.\(key.id)")
                }
            }
            if board.id != SymbolBoardStore.stockID && board.id != SymbolBoardStore.favoritesID {
                Button("Delete board", role: .destructive) {
                    act { store.deleteBoard(board.id) }
                    if error == nil { editingBoardID = nil }
                }.accessibilityIdentifier("keyboard.boards.delete")
            }
        }.disabled(!store.canEdit)
    }
    private func keyPanel(_ board: SymbolBoard, _ key: SymbolBoardKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(symbolBoardPreview(key.text)).font(.system(size: 30)).lineLimit(1)
                .minimumScaleFactor(0.5).frame(maxWidth: .infinity).frame(height: 36)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                Button("Move left") { act { store.moveKey(boardID: board.id, keyID: key.id, by: -1) } }
                Button("Move right") { act { store.moveKey(boardID: board.id, keyID: key.id, by: 1) } }
                Button("Remove key", role: .destructive) {
                    act { store.removeKey(boardID: board.id, keyID: key.id) }
                    if error == nil { editingKeyID = nil }
                }.accessibilityIdentifier("keyboard.boards.removeKey")
            }.font(.system(size: 11))
            ForEach(Array(key.variants.enumerated()), id: \.offset) { index, variant in
                VStack(alignment: .leading, spacing: 4) {
                    Text(symbolBoardPreview(variant)).font(.system(size: 23)).lineLimit(1)
                        .minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .leading).frame(height: 36)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], alignment: .leading, spacing: 6) {
                        Button("Earlier") { editVariants(board, key, index: index, direction: -1) }
                        Button("Later") { editVariants(board, key, index: index, direction: 1) }
                    Button("Remove", role: .destructive) {
                        act {
                            guard let current = store.key(boardID: board.id, keyID: key.id), current == key else { return false }
                            var variants = current.variants; variants.remove(at: index)
                            return store.setVariants(boardID: board.id, keyID: key.id, variants: variants)
                        }
                    }.accessibilityIdentifier("keyboard.boards.variant.remove.\(index)")
                    }
                }.font(.system(size: 11))
            }
            Button("Add variant from Unicode") {
                guard sessionIsCurrent?() == true, store.key(boardID: board.id, keyID: key.id) == key else { return }
                pick(.init(boardID: board.id, keyID: key.id))
            }.accessibilityIdentifier("keyboard.boards.addVariantUnicode")
            Button("Type a simple variant") { begin(.variant(board.id, key.id)) }
                .accessibilityIdentifier("keyboard.boards.addVariantLocal")
        }.disabled(!store.canEdit)
    }
    private func editVariants(_ board: SymbolBoard, _ key: SymbolBoardKey, index: Int, direction: Int) {
        act {
            guard let current = store.key(boardID: board.id, keyID: key.id), current == key,
                  current.variants.indices.contains(index + direction) else { return false }
            var variants = current.variants; variants.swapAt(index, index + direction)
            return store.setVariants(boardID: board.id, keyID: key.id, variants: variants)
        }
    }
    private var entryPanel: some View {
        VStack(spacing: 6) {
            Text(entry.isEmpty ? "Use the local keys below" : symbolBoardPreview(entry))
                .font(.system(size: 17)).lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 36)
                .accessibilityIdentifier("keyboard.boards.entry").accessibilityValue(entry)
            ForEach([Array("1234567890"), Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm.-_")], id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { key in
                        let text = uppercase ? String(key).uppercased() : String(key)
                        Button(text) {
                            guard sessionIsCurrent?() == true, entry.unicodeScalars.count + text.unicodeScalars.count <= 128 else { return }
                            entry += text
                        }.frame(maxWidth: .infinity, minHeight: 36)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                            .accessibilityIdentifier("keyboard.boards.pad.\(key)")
                    }
                }
            }
            HStack {
                Button(uppercase ? "abc" : "ABC") { uppercase.toggle() }.accessibilityIdentifier("keyboard.boards.pad.shift")
                Button("Space") { if sessionIsCurrent?() == true && entry.unicodeScalars.count < 128 { entry += " " } }
                    .frame(maxWidth: .infinity).accessibilityIdentifier("keyboard.boards.pad.space")
                Button("Delete") { if !entry.isEmpty { entry.removeLast() } }.accessibilityIdentifier("keyboard.boards.pad.delete")
                Button("Save") { saveEntry() }.accessibilityIdentifier("keyboard.boards.pad.save")
            }.font(.system(size: 12))
        }
    }
    private func saveEntry() {
        guard let purpose = entryPurpose else { return }
        act {
            switch purpose {
            case .create: return store.createBoard(named: entry) != nil
            case .rename(let id): return store.renameBoard(id, to: entry)
            case .variant(let boardID, let keyID):
                guard let key = store.key(boardID: boardID, keyID: keyID) else { return false }
                return store.setVariants(boardID: boardID, keyID: keyID, variants: key.variants + [entry])
            }
        }
        if error == nil { entryPurpose = nil; entry = "" }
    }
}

/// Opaque configuration owns the complete proposed overlay area. A clipped,
/// finite ScrollView keeps large boards and the local pad inside that area.
private extension View {
    func symbolBoardOpaquePanel() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: .systemBackground))
            .contentShape(Rectangle())
            .clipped()
    }
}

/// The persistent editor has a document/mode lifetime, but every physical
/// press takes a fresh strict resize-generation guard at touch-down.
private struct SymbolBoardConfigurationButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let guardFactory: () -> (() -> Bool)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                SymbolBoardConfigurationTouchOverlay(enabled: isEnabled, guardFactory: guardFactory,
                    trigger: { configuration.trigger() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                // Accessibility activation is atomic, rather than a held
                // physical press. It still requires the current strict scope.
                guard isEnabled, let current = guardFactory(), current() else { return }
                configuration.trigger()
            }
    }
}

private struct SymbolBoardConfigurationTouchOverlay: UIViewRepresentable {
    let enabled: Bool
    let guardFactory: () -> (() -> Bool)?
    let trigger: () -> Void

    func makeUIView(context: Context) -> KeyboardConfigurationTouchView {
        let view = KeyboardConfigurationTouchView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.02)
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }
    func updateUIView(_ view: KeyboardConfigurationTouchView, context: Context) {
        view.isEnabled = enabled
        view.isUserInteractionEnabled = enabled
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        // Reconfiguration cancels an old label/action press. A later down
        // snapshots the fresh factory; an old up can never retarget to it.
        let capture = guardFactory
        let perform = trigger
        view.configure(contextIdentifier: UUID()) { [weak view] in
            guard view?.isEnabled == true, let current = capture(), current() else { return { false } }
            return { [weak view] in
                guard view?.isEnabled == true, current() else { return false }
                perform()
                return true
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: KeyboardConfigurationTouchView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width >= 0, height >= 0 else { return nil }
        return CGSize(width: width, height: height)
    }
    static func dismantleUIView(_ view: KeyboardConfigurationTouchView, coordinator: ()) {
        view.isEnabled = false
        view.isUserInteractionEnabled = false
        view.configure(contextIdentifier: UUID()) { { false } }
    }
}

/// A visible substitute is presentation only; insertion always uses the
/// original string, including NUL, controls and standalone combining marks.
func symbolBoardPreview(_ text: String) -> String {
    if text == " " { return "␠" }
    if text == "\n" { return "↵" }
    if text == "\r" { return "␍" }
    if text == "\t" { return "⇥" }
    if text == "\0" { return "␀" }
    guard let first = text.unicodeScalars.first else { return "◌" }
    if text.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }) { return "◌" }
    if [.nonspacingMark, .spacingMark, .enclosingMark].contains(first.properties.generalCategory) { return "◌" + text }
    return text
}

func symbolBoardKeyLabel(_ text: String) -> String {
    let points = text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    return "\(symbolBoardPreview(text)), \(points)"
}
