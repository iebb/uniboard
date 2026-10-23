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
        guard url.scheme == "https", url.host == "raw.githubusercontent.com", url.user == nil, url.password == nil,
              url.port == nil, url.path.hasPrefix("/google/fonts/") else { throw FontLibraryFailure.invalidFile }
        let components = url.path.split(separator: "/").map(String.init)
        guard components.count >= 4, url.query == nil, url.fragment == nil,
              (try? GoogleFontURLPolicy.url(commit: components[2], path: components.dropFirst(3).joined(separator: "/"))) == url else { throw FontLibraryFailure.invalidFile }
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

@MainActor
final class GoogleFontDownloadCoordinator: ObservableObject {
    @Published private(set) var states: [String: GoogleFontDownloadState] = [:]
    private let catalog: GoogleFontCatalogSnapshot
    private let trustedCatalog: GoogleFontCatalog?
    @Published private(set) var libraryFailure: FontLibraryFailure?
    private let store: CustomFontStore
    private let transport: any GoogleFontTransport
    private var jobs: [String: Task<String, Error>] = [:]
    private var tokens: [String: UUID] = [:]
    private var active = 0
    private var removing: Set<String> = []

    init(catalog: GoogleFontCatalogSnapshot, store: CustomFontStore = .shared,
         transport: any GoogleFontTransport = PinnedGoogleFontTransport()) {
        self.catalog = catalog; self.store = store; self.transport = transport
        trustedCatalog = try? GoogleFontCatalog(snapshot: catalog)
        do {
            let state = try store.readLibraryState()
            for file in catalog.files {
                if trustedCatalog == nil { states[file.id] = .failed(.invalidFile) }
                else if let id = state.assetIDs[file.id] { states[file.id] = .downloaded(assetID: id) }
                else { states[file.id] = .ready }
            }
        } catch {
            libraryFailure = (error as? FontLibraryFailure) ?? .storageFailure
        }
    }

    func download(styleID: String) async throws {
        guard let trustedCatalog else { throw FontLibraryFailure.invalidFile }
        guard let family = catalog.families.first(where: { $0.styles.contains(where: { $0.id == styleID }) }),
              let style = family.styles.first(where: { $0.id == styleID }),
              let file = catalog.files.first(where: { $0.id == style.fileID }) else { throw FontLibraryFailure.invalidFile }
        guard !removing.contains(file.id) else { throw CancellationError() }
        do {
            let current = try store.readLibraryState()
            libraryFailure = nil
            if let id = current.assetIDs[file.id] {
                // Missing bytes must go through a validated redownload/repair.
                if let url = store.url(forRelativePath: id), FileManager.default.fileExists(atPath: url.path) {
                    states[file.id] = .downloaded(assetID: id); return
                }
            }
            if case .downloaded = states[file.id] { states[file.id] = .ready }
        } catch {
            let failure = (error as? FontLibraryFailure) ?? .storageFailure
            libraryFailure = failure; states[file.id] = .failed(failure); throw failure
        }
        if let job = jobs[file.id] { _ = try await job.value; return }
        guard file.unavailableReason == nil else { states[file.id] = .failed(.invalidFile); throw FontLibraryFailure.invalidFile }
        guard file.bytes <= Int64(CustomFontStore.maximumBytes) else { states[file.id] = .failed(.tooLarge(limitBytes: Int64(CustomFontStore.maximumBytes))); throw FontLibraryFailure.tooLarge(limitBytes: Int64(CustomFontStore.maximumBytes)) }
        let url = try trustedCatalog.downloadURL(for: file)
        let token = UUID(); tokens[file.id] = token; states[file.id] = .queued
        let job = Task<String, Error> { [self] in
            // Cooperative queue: waiting tasks never own a network session.
            while active >= 2 { try await Task.sleep(nanoseconds: 40_000_000) }
            try Task.checkCancellation()
            active += 1
            defer { active -= 1 }
            states[file.id] = .downloading(received: 0, expected: file.bytes > 0 ? file.bytes : nil)
            let data = try await transport.fetch(url: url, limit: Int64(CustomFontStore.maximumBytes)) { [weak self] received, expected in
                Task { @MainActor in
                    guard let self, self.tokens[file.id] == token, case .downloading = self.states[file.id] else { return }
                    self.states[file.id] = .downloading(received: received, expected: expected)
                }
            }
            try Task.checkCancellation()
            guard Int64(data.count) == file.bytes else { throw FontLibraryFailure.invalidFile }
            states[file.id] = .preparing
            let licenses = file.licenseIDs.compactMap { id in catalog.licenses.first { $0.id == id } }.map {
                FontLibraryLicense(id: $0.id, name: $0.name, repositoryPath: $0.repositoryPath, sha256: $0.sha256, text: $0.text)
            }
            guard licenses.count == file.licenseIDs.count else { throw FontLibraryFailure.invalidFile }
            let receipt = FontLibraryReceipt(fileID: file.id, repositoryCommit: catalog.repositoryCommit, repositoryPath: file.repositoryPath,
                                             snapshotDate: catalog.snapshotDate, sha256: file.sha256, licenses: licenses)
            let faces = catalog.families.flatMap { family in family.styles.filter { $0.fileID == file.id }.map { style in
                FontFaceRecord(id: .init(rawValue: "google:\(file.id):\(style.id)"), family: family.name, style: style.name,
                               postScriptName: style.postScriptName, source: .downloaded,
                               locator: .process(postScriptName: style.postScriptName, variations: style.variationInstance ?? [:]), assetID: nil)
            } }
            let worker = Task.detached { [store] in
                try Task.checkCancellation()
                return try store.installGoogleFont(data: data, receipt: receipt, faces: faces, expectedPostScriptNames: file.expectedPostScriptNames,
                                                   checkCancellation: { try Task.checkCancellation() })
            }
            return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        }
        jobs[file.id] = job
        do {
            let id = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
            if tokens[file.id] == token { states[file.id] = .downloaded(assetID: id); jobs[file.id] = nil }
        } catch {
            if tokens[file.id] == token {
                states[file.id] = error is CancellationError ? .cancelled : .failed(Self.failure(error))
                jobs[file.id] = nil
            }
            throw error
        }
    }

    func cancel(fileID: String) async throws {
        guard let job = jobs[fileID] else { return }
        let token = tokens[fileID]
        job.cancel()
        // Wait for the commit boundary: if publication won, retain success.
        do { let id = try await job.value; if tokens[fileID] == token { states[fileID] = .downloaded(assetID: id) } }
        catch { if tokens[fileID] == token { states[fileID] = .cancelled } }
        if tokens[fileID] == token { jobs[fileID] = nil }
    }

    func remove(fileID: String) async throws {
        guard trustedCatalog != nil, catalog.files.contains(where: { $0.id == fileID }) else { throw FontLibraryFailure.invalidFile }
        guard removing.insert(fileID).inserted else { return }
        defer { removing.remove(fileID) }
        try await cancel(fileID: fileID)
        try await Task.detached { [store] in try store.removeGoogleFont(fileID: fileID) }.value
        tokens[fileID] = UUID(); states[fileID] = .ready
    }

    private static func failure(_ error: Error) -> FontLibraryFailure {
        if let failure = error as? FontLibraryFailure { return failure }
        if let error = error as? URLError { return error.code == .notConnectedToInternet ? .offline : .transport }
        return .storageFailure
    }
}
