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
                    NavigationLink {
                        FontFaceDetailView(family: family, catalog: catalog, coordinator: coordinator, text: text)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(family.name).font(.body.weight(.semibold))
                            Text("\(family.styles.count) styles").font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 52)
                    }.accessibilityIdentifier("googleFonts.family.\(family.name)")
                }
            }
        }
        .navigationTitle("Google Fonts")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search fonts by name")
        .modifier(FontSearchToolbarVisibility())
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
