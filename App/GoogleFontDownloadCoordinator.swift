import Foundation
import Combine
import CryptoKit

/// Injectable app-only transport; implementations must enforce limit before appending bytes.
protocol GoogleFontTransport: Sendable {
    func fetch(url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Data
}

enum GoogleFontURLPolicy {
    static func url(commit: String, path: String) throws -> URL {
        guard commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              !path.isEmpty, !path.contains("\\"), !path.contains("%"), !path.contains("?"), !path.contains("#"),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let url = URL(string: "https://raw.githubusercontent.com/google/fonts/\(commit)/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")") else { throw FontLibraryFailure.invalidFile }
        return url
    }

    /// A pinned single-style instance: https://fonts.gstatic.com/s/<family>/v<n>/<name>.ttf only.
    static func instanceURL(path: String) throws -> URL {
        guard GoogleFontCatalog.safeInstancePath(path),
              let url = URL(string: "https://\(GoogleFontCatalog.instanceHost)/\(path)") else { throw FontLibraryFailure.invalidFile }
        return url
    }

    /// The only two shapes the transport will fetch, each re-derived from its own parts.
    static func isPinned(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        switch url.host {
        case "raw.githubusercontent.com":
            guard url.path.hasPrefix("/google/fonts/") else { return false }
            let components = url.path.split(separator: "/").map(String.init)
            return components.count >= 4 && (try? Self.url(commit: components[2], path: components.dropFirst(3).joined(separator: "/"))) == url
        case GoogleFontCatalog.instanceHost:
            return (try? instanceURL(path: String(url.path.dropFirst()))) == url
        default:
            return false
        }
    }
}
final class RejectFontRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { completionHandler(.performDefaultHandling, nil) }
        else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}
struct PinnedGoogleFontTransport: GoogleFontTransport {
    func fetch(url: URL, limit: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Data {
        guard GoogleFontURLPolicy.isPinned(url) else { throw FontLibraryFailure.invalidFile }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: RejectFontRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url else { throw FontLibraryFailure.transport }
        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        if let expected, expected > limit { throw FontLibraryFailure.tooLarge(limitBytes: limit) }
        var data = Data()
        var hasher = SHA256()
        var chunk = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard Int64(data.count + chunk.count) < limit else { throw FontLibraryFailure.tooLarge(limitBytes: limit) }
            chunk.append(byte)
            if chunk.count == 65536 {
                hasher.update(data: chunk); data.append(chunk); chunk.removeAll(keepingCapacity: true)
                progress(Int64(data.count), expected)
            }
        }
        hasher.update(data: chunk); data.append(chunk)
        _ = hasher.finalize() // Storage verifies against pinned digest before atomic publication.
        progress(Int64(data.count), expected)
        return data
    }
}

/// What one Download row fetches: the whole repository file, or the style's pinned single-style instance.
enum GoogleFontDownloadScope: Equatable, Sendable { case file, instance }

@MainActor
final class GoogleFontDownloadCoordinator: ObservableObject {
    /// Keyed by download id: a repository file id, or a `GoogleFontInstance.id` ("gstatic:s/…").
    @Published private(set) var states: [String: GoogleFontDownloadState] = [:]
    /// Imported/downloaded files and installed references share the existing 16-entry quota.
    @Published private(set) var libraryFileCount = 0
    private let catalog: GoogleFontCatalogSnapshot
    private let trustedCatalog: GoogleFontCatalog?
    @Published private(set) var libraryFailure: FontLibraryFailure?
    private let store: CustomFontStore
    private let transport: any GoogleFontTransport
    private var jobs: [String: Task<String, Error>] = [:]
    private var tokens: [String: UUID] = [:]
    private var active = 0
    private var removing: Set<String> = []

    /// One download, resolved from the catalog: never from a payload.
    private struct Source {
        let id: String
        let url: URL?
        let bytes: Int64
        let sha256: String
        let expectedPostScriptNames: [String]
        let file: GoogleFontFile
        let kind: FontLibrarySourceKind
        let faces: [FontFaceRecord]
    }

    init(catalog: GoogleFontCatalogSnapshot, store: CustomFontStore = .shared,
         transport: any GoogleFontTransport = PinnedGoogleFontTransport()) {
        self.catalog = catalog; self.store = store; self.transport = transport
        trustedCatalog = try? GoogleFontCatalog(snapshot: catalog)
        do {
            let state = try store.readLibraryState()
            libraryFileCount = state.snapshot.customEntryCount
            let ids = catalog.files.map(\.id) + catalog.families.flatMap { $0.styles.compactMap { $0.instance?.id } }
            for id in ids {
                if trustedCatalog == nil { states[id] = .failed(.invalidFile) }
                else if let asset = state.assetIDs[id] { states[id] = .downloaded(assetID: asset) }
                else { states[id] = .ready }
            }
        } catch {
            libraryFailure = (error as? FontLibraryFailure) ?? .storageFailure
        }
    }

    /// Reconcile idle rows with authoritative membership after imports or file
    /// management elsewhere. Retained immutable bytes do not mean a receipt is
    /// still downloaded. Never overwrite an in-flight job's progress/state.
    func refreshLibrary() {
        do {
            let state = try store.readLibraryState()
            libraryFileCount = state.snapshot.customEntryCount
            libraryFailure = nil
            let ids = Set(states.keys).union(catalog.files.map(\.id))
                .union(catalog.families.flatMap { $0.styles.compactMap { $0.instance?.id } })
            for id in ids where jobs[id] == nil && !removing.contains(id) {
                guard trustedCatalog != nil else { states[id] = .failed(.invalidFile); continue }
                if let asset = state.assetIDs[id] {
                    states[id] = .downloaded(assetID: asset)
                } else if case .downloaded = states[id] {
                    states[id] = .ready
                } else if states[id] == nil {
                    states[id] = .ready
                }
            }
        } catch {
            // Unreadable storage is not evidence that every receipt was removed.
            libraryFailure = (error as? FontLibraryFailure) ?? .storageFailure
        }
    }

    var freeFileSpaces: Int { max(0, CustomFontStore.maximumFonts - libraryFileCount) }

    private func source(styleID: String, scope: GoogleFontDownloadScope, trusted: GoogleFontCatalog) throws -> Source {
        guard let family = catalog.families.first(where: { $0.styles.contains(where: { $0.id == styleID }) }),
              let style = family.styles.first(where: { $0.id == styleID }),
              let file = trusted.file(id: style.fileID) else { throw FontLibraryFailure.invalidFile }
        switch scope {
        case .file:
            let faces = catalog.families.flatMap { family in family.styles.filter { $0.fileID == file.id }.map { style in
                FontFaceRecord(id: .init(rawValue: "google:\(file.id):\(style.id)"), family: family.name, style: style.name,
                               postScriptName: style.postScriptName, source: .downloaded,
                               locator: .process(postScriptName: style.postScriptName, variations: style.variationInstance ?? [:]), assetID: nil,
                               equivalents: style.instance.map { [.file(relativePath: "", sha256: $0.sha256, faceIndex: 0, variations: [:])] })
            } }
            return Source(id: file.id, url: try? trusted.downloadURL(for: file), bytes: file.bytes, sha256: file.sha256, expectedPostScriptNames: file.expectedPostScriptNames,
                          file: file, kind: .repository, faces: faces)
        case .instance:
            guard let instance = style.instance, trusted.instance(id: instance.id) == instance else { throw FontLibraryFailure.invalidFile }
            // Every catalog style this static file stands in for (repeated named instances share it).
            let faces = catalog.families.flatMap { family in family.styles.filter { $0.instance == instance }.map { style in
                FontFaceRecord(id: .init(rawValue: "google:\(GoogleFontCatalog.instanceIDPrefix)\(style.id)"), family: family.name, style: style.name,
                               postScriptName: instance.postScriptName, source: .downloaded,
                               locator: .process(postScriptName: instance.postScriptName, variations: [:]), assetID: nil,
                               equivalents: trusted.file(id: style.fileID).map { [.file(relativePath: "", sha256: $0.sha256, faceIndex: 0, variations: style.variationInstance ?? [:])] })
            } }
            return Source(id: instance.id, url: try trusted.downloadURL(for: instance), bytes: instance.bytes, sha256: instance.sha256,
                          expectedPostScriptNames: [instance.postScriptName], file: file, kind: .gstatic, faces: faces)
        }
    }

    func download(styleID: String, scope: GoogleFontDownloadScope = .file) async throws {
        guard let trustedCatalog else {
            if let id = catalog.families.flatMap(\.styles).first(where: { $0.id == styleID }).map({ scope == .file ? $0.fileID : ($0.instance?.id ?? $0.fileID) }) {
                states[id] = .failed(.invalidFile)
            }
            throw FontLibraryFailure.invalidFile
        }
        let source = try source(styleID: styleID, scope: scope, trusted: trustedCatalog)
        let file = source.file
        guard !removing.contains(source.id) else { throw CancellationError() }
        do {
            let current = try store.readLibraryState()
            libraryFailure = nil
            libraryFileCount = current.snapshot.customEntryCount
            if let id = current.assetIDs[source.id] {
                // Missing bytes must go through a validated redownload/repair.
                if let url = store.url(forRelativePath: id), FileManager.default.fileExists(atPath: url.path) {
                    // readLibraryState enriches old records from the bundled
                    // identities in memory, including this no-download path.
                    // Do not reinstall or rewrite an existing 1.3 record.
                    states[source.id] = .downloaded(assetID: id); return
                }
            }
            if case .downloaded = states[source.id] { states[source.id] = .ready }
        } catch {
            let failure = (error as? FontLibraryFailure) ?? .storageFailure
            libraryFailure = failure; states[source.id] = .failed(failure); throw failure
        }
        if let job = jobs[source.id] { _ = try await job.value; return }
        guard file.unavailableReason == nil, let url = source.url else {
            states[source.id] = .failed(.invalidFile); throw FontLibraryFailure.invalidFile
        }
        guard source.bytes <= Int64(CustomFontStore.maximumBytes) else { states[source.id] = .failed(.tooLarge(limitBytes: Int64(CustomFontStore.maximumBytes))); throw FontLibraryFailure.tooLarge(limitBytes: Int64(CustomFontStore.maximumBytes)) }
        let id = source.id
        let token = UUID(); tokens[id] = token; states[id] = .queued
        let job = Task<String, Error> { [self] in
            // Cooperative queue: waiting tasks never own a network session.
            while active >= 2 { try await Task.sleep(nanoseconds: 40_000_000) }
            try Task.checkCancellation()
            active += 1
            defer { active -= 1 }
            states[id] = .downloading(received: 0, expected: source.bytes > 0 ? source.bytes : nil)
            let data = try await transport.fetch(url: url, limit: Int64(CustomFontStore.maximumBytes)) { [weak self] received, expected in
                Task { @MainActor in
                    guard let self, self.tokens[id] == token, case .downloading = self.states[id] else { return }
                    self.states[id] = .downloading(received: received, expected: expected)
                }
            }
            try Task.checkCancellation()
            guard Int64(data.count) == source.bytes else { throw FontLibraryFailure.invalidFile }
            states[id] = .preparing
            // The repository file's license notices apply to its gstatic instance too.
            let licenses = file.licenseIDs.compactMap { id in catalog.licenses.first { $0.id == id } }.map {
                FontLibraryLicense(id: $0.id, name: $0.name, repositoryPath: $0.repositoryPath, sha256: $0.sha256, text: $0.text)
            }
            guard licenses.count == file.licenseIDs.count else { throw FontLibraryFailure.invalidFile }
            let receipt = FontLibraryReceipt(fileID: id, repositoryCommit: catalog.repositoryCommit, repositoryPath: file.repositoryPath,
                                             snapshotDate: catalog.snapshotDate, sha256: source.sha256, licenses: licenses,
                                             sourceKind: source.kind, sourceURL: url.absoluteString)
            let worker = Task.detached { [store] in
                try Task.checkCancellation()
                return try store.installGoogleFont(data: data, receipt: receipt, faces: source.faces, expectedPostScriptNames: source.expectedPostScriptNames,
                                                   checkCancellation: { try Task.checkCancellation() })
            }
            return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        }
        jobs[id] = job
        do {
            let asset = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
            if tokens[id] == token { states[id] = .downloaded(assetID: asset); jobs[id] = nil }
            refreshLibrary()
        } catch {
            if tokens[id] == token {
                states[id] = error is CancellationError ? .cancelled : .failed(Self.failure(error))
                jobs[id] = nil
            }
            throw error
        }
    }

    /// `fileID` is any download id: a repository file or a gstatic instance.
    func cancel(fileID: String) async throws {
        guard let job = jobs[fileID] else { return }
        let token = tokens[fileID]
        job.cancel()
        // Wait for the commit boundary: if publication won, retain success.
        do { let id = try await job.value; if tokens[fileID] == token { states[fileID] = .downloaded(assetID: id) } }
        catch { if tokens[fileID] == token { states[fileID] = .cancelled } }
        if tokens[fileID] == token { jobs[fileID] = nil }
    }

    /// Removes exactly one downloaded file; other files supplying the same styles stay.
    func remove(fileID: String) async throws {
        guard let trustedCatalog, trustedCatalog.file(id: fileID) != nil || trustedCatalog.instance(id: fileID) != nil else { throw FontLibraryFailure.invalidFile }
        guard removing.insert(fileID).inserted else { return }
        defer { removing.remove(fileID) }
        try await cancel(fileID: fileID)
        try await Task.detached { [store] in try store.removeGoogleFont(fileID: fileID) }.value
        tokens[fileID] = UUID(); states[fileID] = .ready
        refreshLibrary()
    }

    private static func failure(_ error: Error) -> FontLibraryFailure {
        if let failure = error as? FontLibraryFailure { return failure }
        if let error = error as? URLError { return error.code == .notConnectedToInternet ? .offline : .transport }
        return .storageFailure
    }
}
