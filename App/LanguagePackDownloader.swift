import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sanitized failures: no URL, server body, headers, credentials, or file paths.
public enum LanguagePackDownloadError: Error, Equatable, Sendable {
    case invalidSource
    case cancelled
    case network(code: Int)
    case httpStatus(Int)
    case rejectedRedirect
    case verification(Verification)
    case storage(operation: String, code: Int)

    public enum Verification: String, Equatable, Sendable {
        case response, advertisedSize, actualSize, sha256
    }
}

/// One budget per explicit user operation, shared across Mandarin's five files.
/// Retries start a fresh GET; there is no resume data or persisted/relaunch work.
public final class LanguagePackRetryBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var used = 0
    public init() {}
    fileprivate func claim() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard used < 2 else { return nil }
        used += 1
        return used
    }
}

/// Containing-app transport only. Register the app's BUNDLED audited catalog here;
/// never populate trustedSources from imported configuration or a downloaded manifest.
/// There is deliberately no arbitrary URL/request/header/authentication API.
public struct LanguagePackDownloader: Sendable {
    private let trustedSources: [LanguagePackDescriptor]
    private let configurationFactory: @Sendable () -> URLSessionConfiguration
    private let retrySleep: @Sendable (UInt64) async throws -> Void

    /// The factory is optional test injection (for example, a URLProtocol fixture).
    /// It must return a fresh configuration. Cache, cookies, credentials and custom
    /// headers are disabled even on injected configurations; background sessions fail.
    public init(trustedSources: [LanguagePackDescriptor],
                configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.init(trustedSources: trustedSources,
                  retrySleep: { try await Task.sleep(nanoseconds: $0) }, configuration: configuration)
    }

    /// Internal delay-only seam: tests still execute real URLSession transfers,
    /// verification, cleanup and retry budgeting. Production uses cancellable sleep.
    init(trustedSources: [LanguagePackDescriptor],
         retrySleep: @escaping @Sendable (UInt64) async throws -> Void,
         configuration: @escaping @Sendable () -> URLSessionConfiguration) {
        self.trustedSources = trustedSources
        self.configurationFactory = configuration
        self.retrySleep = retrySleep
    }

    /// Returns a size/SHA-256 verified on-disk archive. Caller owns and must remove
    /// the returned file after extraction. scratchDirectory must already exist and
    /// be an app-owned private directory, not a shared/user-selected location.
    ///
    /// Progress is synchronous on the serial utility delegate queue, NEVER MainActor.
    /// UI callers must explicitly hop, e.g. `Task { @MainActor in model.progress = p }`.
    /// No callbacks occur after this method resumes its caller.
    public func download(source: LanguagePackDescriptor, scratchDirectory: URL,
                         retryBudget: LanguagePackRetryBudget = LanguagePackRetryBudget(),
                         retrying: @escaping @Sendable (Int) -> Void = { _ in },
                         progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try await Self.withRetries(budget: retryBudget, retrying: retrying, sleep: retrySleep) {
            try await downloadOnce(source: source, scratchDirectory: scratchDirectory, progress: progress)
        }
    }

    /// Internal injected delay/attempt seams exercise policy without real network
    /// or wall-clock delays. Production waits are bounded at 1 and 2 seconds.
    static func withRetries<T>(budget: LanguagePackRetryBudget,
                               retrying: @escaping @Sendable (Int) -> Void = { _ in },
                               sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
                               attempt: () async throws -> T) async throws -> T {
        while true {
            if Task.isCancelled { throw LanguagePackDownloadError.cancelled }
            do { return try await attempt() }
            catch {
                if Task.isCancelled { throw LanguagePackDownloadError.cancelled }
                guard let failure = error as? LanguagePackDownloadError,
                      isTransient(failure), let retry = budget.claim() else { throw error }
                retrying(retry)
                do { try await sleep(UInt64(retry) * 1_000_000_000) }
                catch is CancellationError { throw LanguagePackDownloadError.cancelled }
            }
        }
    }

    static func isTransient(_ error: LanguagePackDownloadError) -> Bool {
        switch error {
        case .network(let code):
            return [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                    NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                    NSURLErrorNotConnectedToInternet].contains(code)
        case .httpStatus(let status): return [408, 429, 500, 502, 503, 504].contains(status)
        default: return false // No TLS/auth/redirect/size/hash/security/storage retries.
        }
    }

    private func downloadOnce(source: LanguagePackDescriptor, scratchDirectory: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard trustedSources.contains(source), (try? source.validate()) != nil else {
            throw LanguagePackDownloadError.invalidSource
        }
        let configuration = configurationFactory()
        guard configuration.identifier == nil else { throw LanguagePackDownloadError.invalidSource }
        // Copy first; do not mutate a configuration retained by an injecting caller.
        let isolated = configuration.copy() as! URLSessionConfiguration
        isolated.urlCache = nil
        isolated.requestCachePolicy = .reloadIgnoringLocalCacheData
        isolated.httpCookieStorage = nil
        isolated.httpShouldSetCookies = false
        isolated.urlCredentialStorage = nil
        isolated.httpAdditionalHeaders = nil
        isolated.timeoutIntervalForRequest = 60
        isolated.timeoutIntervalForResource = 600
        let transfer = Transfer(source: source, scratch: scratchDirectory,
                                configuration: isolated, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(continuation)
            }
        } onCancel: {
            transfer.cancel()
        }
    }
}

/// Actual synchronization behind @unchecked Sendable:
/// - all lifecycle, continuation, session, file and verification state is confined
///   to queue (maxConcurrentOperationCount = 1);
/// - ONLY cancellation/finished/task are shared with the caller's cancellation
///   handler, and every read/write of those fields takes cancellationLock;
/// - source/scratch/configuration/progress/queue are immutable after construction.
/// URLSession retains its delegate until invalidated; every terminal path invalidates.
private final class Transfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let source: LanguagePackDescriptor
    private let scratch: URL
    private let configuration: URLSessionConfiguration
    private let progress: @Sendable (Double) -> Void
    private let queue: OperationQueue
    private let cancellationLock = NSLock()
    private var cancelled = false
    private var finished = false
    private var cancellableTask: URLSessionDownloadTask?
    // Serial queue confined below.
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var movedFile: URL?
    private var failure: LanguagePackDownloadError?

    init(source: LanguagePackDescriptor, scratch: URL, configuration: URLSessionConfiguration,
         progress: @escaping @Sendable (Double) -> Void) {
        self.source = source
        self.scratch = scratch
        self.configuration = configuration
        self.progress = progress
        queue = OperationQueue()
        queue.name = "Uniboard.LanguagePackDownload"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        super.init()
    }

    func start(_ continuation: CheckedContinuation<URL, Error>) {
        queue.addOperation { [self] in
            self.continuation = continuation
            if isCancelled { finish(.failure(.cancelled)); return }
            do {
                guard scratch.isFileURL else { throw LanguagePackDownloadError.storage(operation: "scratch directory", code: 0) }
                let attributes = try FileManager.default.attributesOfItem(atPath: scratch.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw LanguagePackDownloadError.storage(operation: "scratch directory", code: 0)
                }
            } catch let error as LanguagePackDownloadError {
                finish(.failure(error)); return
            } catch {
                finish(.failure(.storage(operation: "scratch directory", code: (error as NSError).code))); return
            }
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            let task = session.downloadTask(with: request(source.sourceURL))
            cancellationLock.lock()
            cancellableTask = task
            let shouldCancel = cancelled
            cancellationLock.unlock()
            // Covers cancellation before continuation installation, during creation,
            // and between attaching task and resume. Pre-cancel avoids relying on a
            // suspended task ever delivering didCompleteWithError.
            if shouldCancel {
                task.cancel()
                finish(.failure(.cancelled))
                return
            }
            progress(0)
            task.resume()
        }
    }

    func cancel() {
        cancellationLock.lock()
        guard !finished else { cancellationLock.unlock(); return }
        cancelled = true
        let task = cancellableTask
        cancellationLock.unlock()
        task?.cancel()
    }

    private var isCancelled: Bool {
        cancellationLock.lock(); defer { cancellationLock.unlock() }
        return cancelled
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        return request
    }

    private func trusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.fragment == nil
        && (url.port == nil || url.port == 443)
        && source.allowedHosts.contains(url.host?.lowercased() ?? "")
    }

    /// URLSession decodes HTTP content codings before writing the downloaded file.
    /// Content-Length (and sometimes the delegate's expected count) instead describes
    /// the encoded representation. This is independent of an archive's .tar.gz format.
    private func hasEncodedBody(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse,
              let coding = response.value(forHTTPHeaderField: "Content-Encoding") else { return false }
        return coding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "identity"
    }

    private func advertisedSizeFailure(_ length: Int64, encoded: Bool) -> LanguagePackDownloadError? {
        // Unknown (-1) lengths are normal, including Foundation's decoded gzip
        // responses. Encoded lengths still have a hard transport ceiling; only
        // identity lengths can be compared to the pinned DECODED byte count.
        if length >= 0 && (length > LanguagePackDescriptor.maximumArchiveBytes
                          || (!encoded && length != source.archiveByteCount)) {
            return .verification(.advertisedSize)
        }
        return nil
    }

    private func responseFailure(_ response: URLResponse?) -> LanguagePackDownloadError? {
        guard let response = response as? HTTPURLResponse,
              let url = response.url, trusted(url) else { return .verification(.response) }
        guard response.statusCode == 200 else { return .httpStatus(response.statusCode) }
        if let coding = response.value(forHTTPHeaderField: "Content-Encoding") {
            // These are Foundation's supported HTTP content codings. Reject unknown
            // or stacked codings rather than treating arbitrary metadata as a reason
            // to relax identity length checks. No manual decompression/trust bypass.
            guard ["identity", "gzip", "deflate", "br"].contains(
                coding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                return .verification(.response)
            }
        }
        let encoded = hasEncodedBody(response)
        if let error = advertisedSizeFailure(response.expectedContentLength, encoded: encoded) { return error }
        // Reject malformed/ambiguous Content-Length even when it is a transport
        // length. Never accept it as evidence that the decoded file is verified.
        if let header = response.value(forHTTPHeaderField: "Content-Length") {
            let digits = header.trimmingCharacters(in: .whitespaces)
            guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }),
                  let length = Int64(digits) else { return .verification(.advertisedSize) }
            if let error = advertisedSizeFailure(length, encoded: encoded) { return error }
        }
        return nil
    }

    private func abort(_ error: LanguagePackDownloadError, task: URLSessionTask) {
        if failure == nil { failure = error }
        task.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard !isCancelled, let url = newRequest.url, trusted(url) else {
            failure = isCancelled ? .cancelled : .rejectedRedirect
            completionHandler(nil)
            task.cancel()
            return
        }
        // Rebuild, rather than forwarding cookies/auth or server-supplied headers.
        completionHandler(request(url))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // System TLS trust validation only. No credentials and no trust bypass.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if isCancelled { downloadTask.cancel(); return }
        if let error = responseFailure(downloadTask.response) { abort(error, task: downloadTask); return }
        guard totalBytesWritten >= 0, totalBytesWritten <= source.archiveByteCount else {
            abort(.verification(.actualSize), task: downloadTask); return
        }
        if let error = advertisedSizeFailure(totalBytesExpectedToWrite, encoded: hasEncodedBody(downloadTask.response)) {
            abort(error, task: downloadTask); return
        }
        progress(min(0.99, max(0, Double(totalBytesWritten) / Double(source.archiveByteCount))))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if isCancelled { failure = .cancelled; return }
        if let error = responseFailure(downloadTask.response) { failure = error; return }
        guard failure == nil else { return }
        // URLSession deletes location when this delegate method returns. Always
        // move it synchronously now, and retain only our own UUID-named scratch file.
        let destination = scratch.appendingPathComponent("language-pack-" + UUID().uuidString + ".tar.gz")
        movedFile = destination // Also own cleanup if a cross-volume move fails after copying.
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = .storage(operation: "retain downloaded archive", code: (error as NSError).code)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isCancelled { finish(.failure(.cancelled)); return }
        if let failure { finish(.failure(failure)); return }
        if let error {
            let ns = error as NSError
            finish(.failure(ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
                            ? .cancelled : .network(code: ns.code)))
            return
        }
        if let failure = responseFailure(task.response) { finish(.failure(failure)); return }
        guard let movedFile else { finish(.failure(.verification(.response))); return }
        do {
            try verify(movedFile)
            finish(.success(movedFile))
        } catch let error as LanguagePackDownloadError {
            finish(.failure(error))
        } catch {
            finish(.failure(.storage(operation: "verify downloaded archive", code: (error as NSError).code)))
        }
    }

    private func verify(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value == source.archiveByteCount else {
            throw LanguagePackDownloadError.verification(.actualSize)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var count: Int64 = 0
        while true {
            if isCancelled { throw LanguagePackDownloadError.cancelled }
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty { break }
            count += Int64(chunk.count)
            guard count <= source.archiveByteCount else { throw LanguagePackDownloadError.verification(.actualSize) }
            hasher.update(data: chunk)
        }
        guard count == source.archiveByteCount else { throw LanguagePackDownloadError.verification(.actualSize) }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash == source.archiveSHA256 else { throw LanguagePackDownloadError.verification(.sha256) }
    }

    private func finish(_ proposed: Result<URL, LanguagePackDownloadError>) {
        cancellationLock.lock()
        guard !finished else { cancellationLock.unlock(); return }
        finished = true
        let result: Result<URL, LanguagePackDownloadError> = cancelled ? .failure(.cancelled) : proposed
        cancellableTask = nil
        cancellationLock.unlock()
        if case .failure = result, let movedFile { try? FileManager.default.removeItem(at: movedFile) }
        movedFile = nil
        session?.invalidateAndCancel()
        session = nil
        let completion = continuation
        continuation = nil
        if case .success = result { progress(1) }
        completion?.resume(with: result.mapError { $0 as Error })
    }
}
