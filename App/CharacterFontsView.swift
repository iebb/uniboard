import SwiftUI
import CoreText

let fontPreviewDisclaimer = "Fonts change the preview here. Other apps choose how inserted text looks."
extension Notification.Name {
    static let fontExplorationLibraryChanged = Notification.Name("Uniboard.FontExplorationLibraryChanged")
}

extension FontSource {
    var explorationLabel: String {
        switch self {
        case .system: return "System"
        case .included: return "Included"
        case .downloaded: return "Downloaded"
        case .installed: return "Installed"
        case .imported: return "Imported"
        case .available: return "Available"
        }
    }
}

@MainActor
final class FontExplorationViewModel: ObservableObject {
    @Published private(set) var update: FontScanUpdate?
    @Published private(set) var checking = false
    @Published private(set) var failed = false
    @Published var query = ""
    private let engine: any FontComparing
    private var request = UUID()

    init(engine: any FontComparing = FontComparisonEngine()) { self.engine = engine }

    var faces: [FontFaceRecord] {
        (update?.verified ?? []).filter {
            query.isEmpty || "\($0.family) \($0.style) \($0.postScriptName)".localizedCaseInsensitiveContains(query)
        }
    }
    var countLabel: String {
        guard let update else { return failed ? "Results incomplete" : "Checking available fonts…" }
        if checking || !update.isComplete { return "\(update.checked) of \(update.total) checked" }
        return update.verified.count == 1 ? "1 font available" : "\(update.verified.count) fonts available"
    }
    func scan(_ inspection: FontInspection) async {
        let token = UUID()
        request = token
        checking = true
        failed = false
        update = nil
        await engine.invalidate()
        do {
            for try await value in await engine.scan(inspection) {
                guard !Task.isCancelled, token == request else { return }
                update = value
            }
            guard !Task.isCancelled, token == request else { return }
            checking = false
        } catch {
            guard !Task.isCancelled, token == request else { return }
            checking = false
            failed = true
        }
    }
}

struct CharacterFontsView: View {
    let text: String
    let characterName: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @StateObject private var model = FontExplorationViewModel()
    @State private var presentation = FontPresentation.original
    @State private var refresh = UUID()
    @State private var inspectedFace: FontFaceRecord?
    init(text: String, characterName: String) {
        self.text = text; self.characterName = characterName
    }

    private var inspection: FontInspection {
        FontInspection(originalText: text, characterName: characterName, presentation: presentation)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fonts for This Character").font(.title2.bold())
                        if let face = model.faces.first {
                            VerifiedFontPreview(face: face, inspection: inspection, pointSize: 44)
                                .frame(height: 76).accessibilityHidden(true)
                        }
                        Text(characterName).font(.headline)
                        Text(codepoints(inspection.previewText)).font(.footnote.monospaced()).textSelection(.enabled)
                        Text(fontPreviewDisclaimer).font(.footnote).foregroundStyle(.secondary)
                        if inspection.canChoosePresentation {
                            Picker("Presentation", selection: $presentation) {
                                Text("Original").tag(FontPresentation.original)
                                Text("Text").tag(FontPresentation.text)
                                Text("Emoji").tag(FontPresentation.emoji)
                            }.pickerStyle(.segmented)
                            Text("Presentation changes only this preview. The original Unicode sequence is retained.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !inspection.isApplicable {
                            Text("This character is invisible. Its preview is a placeholder; copying inserts the actual character.")
                            Label("Font preview is not applicable", systemImage: "eye.slash")
                        } else if inspection.usesDottedCircle {
                            Text("The dotted circle is only a preview. This mark combines with the character before it.")
                        }
                    }
                    if model.checking { ProgressView("Checking available fonts…") }
                    Text(model.countLabel).font(.subheadline).foregroundStyle(.secondary)
                    if let update = model.update, update.unknownCount > 0, inspection.isApplicable {
                        Text("Support is unknown for \(update.unknownCount) checked faces. Exact sequence rendering could not be verified.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.failed {
                        VStack(alignment: .leading) {
                            Text("Couldn’t check font support").font(.headline)
                            Text("Try again in a moment. Results are incomplete.")
                            Button("Try Again") { refresh = UUID() }
                        }
                    }
                    if model.faces.isEmpty, !model.query.isEmpty {
                        Text("No matching fonts").font(.headline)
                        Text("Try a different font name.")
                        Button("Clear Search") { model.query = "" }
                    } else if model.faces.isEmpty, model.update?.isComplete == true, inspection.isApplicable, (model.update?.unknownCount ?? 0) == 0 {
                        Text("No matching fonts").font(.headline)
                        Text("None of the fonts available here can preview this character.")
                    }
                    LazyVGrid(columns: columns(width: geometry.size.width), spacing: 12) {
                        ForEach(model.faces) { face in
                            Button {
                                inspectedFace = face
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    VerifiedFontPreview(face: face, inspection: inspection, pointSize: 64)
                                        .frame(minHeight: 120).accessibilityHidden(true)
                                    Text(face.family).font(.subheadline.weight(.semibold))
                                    Text(face.style).font(.caption)
                                    Text(face.source.explorationLabel).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(Color.groupedSurface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("characterFonts.face.\(face.id.rawValue)")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(face.family), \(face.style), preview of \(characterName)")
                            .accessibilityValue(face.source.explorationLabel)
                        }
                    }
                    NavigationLink("Browse Google Fonts") { GoogleFontsView(text: inspection.previewText) }
                        .frame(minHeight: 44)
                }.padding(16).frame(maxWidth: 960)
                    .frame(maxWidth: .infinity)
            }.background(Color.groupedBackground)
        }
        .navigationTitle("Fonts for This Character").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search available fonts")
        .modifier(FontSearchToolbarVisibility())
        .navigationDestination(item: $inspectedFace) { face in
            FontFaceDetailView(face: face, inspection: inspection)
        }
        .task(id: refresh) { await model.scan(inspection) }
        .onChange(of: presentation) { _, _ in refresh = UUID() }
        .onChange(of: phase) { _, value in if value == .active { refresh = UUID() } }
        .onReceive(NotificationCenter.default.publisher(for: .fontExplorationLibraryChanged)) { _ in refresh = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String))) { _ in refresh = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in refresh = UUID() }
    }

    private func columns(width: CGFloat) -> [GridItem] {
        let count = typeSize.isAccessibilitySize || width < 320 ? 1 : width > 700 ? max(2, Int(min(width, 960) / 190)) : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }
}

func codepoints(_ text: String) -> String {
    text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
}

/// iOS 17.0 retains its standard Close-search affordance; newer systems keep Back visible.
struct FontSearchToolbarVisibility: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 17.1, *) {
            content.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
    }
}
