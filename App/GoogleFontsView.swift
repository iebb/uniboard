import SwiftUI

/// Metadata-only browsing: loading/searching never requests a font binary.
@MainActor
final class GoogleFontsViewModel: ObservableObject {
    @Published private(set) var catalog: GoogleFontCatalog?
    @Published private(set) var coordinator: GoogleFontDownloadCoordinator?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published var query = ""

    var families: [GoogleFontFamily] { catalog?.search(query) ?? [] }

    func load() async {
        guard catalog == nil, !isLoading else { return }
        isLoading = true
        failed = false
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try GoogleFontCatalog.load() }.value
            guard !Task.isCancelled else { isLoading = false; return }
            catalog = loaded
            coordinator = GoogleFontDownloadCoordinator(catalog: loaded.snapshot)
        } catch { failed = true }
        isLoading = false
    }
}

struct GoogleFontsView: View {
    var text: String? = nil
    @StateObject private var model = GoogleFontsViewModel()
    /// The pushed family's id.
    @State private var openedFamily: String?

    init(text: String? = nil) { self.text = text }

    var body: some View {
        List {
            Section {
                Text("Find a font and download it when you need it.")
                Text("Downloaded fonts are for use in Uniboard. They aren’t installed for other apps.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let catalog = model.catalog {
                    Text("Catalog snapshot: \(catalog.snapshot.snapshotDate)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.isLoading { ProgressView("Loading fonts…") }
            if model.failed {
                Section {
                    Text("Couldn’t load Google Fonts").font(.headline)
                    Text("Try again in a moment.")
                    Button("Try Again") { Task { await model.load() } }
                }
            }
            if let catalog = model.catalog, let coordinator = model.coordinator {
                FontLibraryStatusView(coordinator: coordinator)
                if model.families.isEmpty {
                    Section {
                        Text("No fonts found").font(.headline)
                        Text("Try a different font name.")
                        Button("Clear Search") { model.query = "" }
                    }
                }
                ForEach(model.families) { family in
                    // Ends search editing before the push; UIKit would
                    // otherwise refocus the field (and keyboard) on Back.
                    Button {
                        FontSearchHeader.endEditing()
                        openedFamily = family.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(family.name).font(.body.weight(.semibold))
                                Text("\(family.styles.count) styles").font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 52)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("googleFonts.family.\(family.name)")
                }
            }
        }
        .navigationDestination(item: $openedFamily) { id in
            if let catalog = model.catalog, let coordinator = model.coordinator,
               let family = catalog.snapshot.families.first(where: { $0.id == id }) {
                FontFaceDetailView(family: family, catalog: catalog, coordinator: coordinator, text: text)
            }
        }
        // The screen owns its search field: a pushed `.searchable` drawer
        // could outlive Back and float above the keyboard on later screens.
        .safeAreaInset(edge: .top, spacing: 0) {
            FontSearchHeader(text: $model.query, placeholder: "Search fonts by name", identifier: "googleFonts.search")
        }
        .navigationTitle("Google Fonts")
        .task { await model.load() }
    }
}

private struct FontLibraryStatusView: View {
    @ObservedObject var coordinator: GoogleFontDownloadCoordinator
    var body: some View {
        if let failure = coordinator.libraryFailure {
            Section {
                Text("Couldn’t read your font library").font(.headline)
                Text(FontDownloadCopy.message(for: failure))
                Text("Catalog results are still available. Existing downloads have not been treated as an empty library.")
                    .font(.footnote)
            }
        }
    }
}
