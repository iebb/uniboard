#if canImport(Uniboard) || canImport(LanguagePackTransport)
import XCTest
import Foundation
import CryptoKit
#if canImport(LanguagePackTransport)
@testable import LanguagePackTransport
#else
@testable import Uniboard
#endif

/// Synthetic decoded URLSession bodies. HTTP content coding is transport metadata,
/// not the archive's format (a .tar.gz archive can itself be HTTP gzip encoded).
final class LanguagePackDownloaderTests: XCTestCase {
    private var scratch: URL!
    private let payload = Data(repeating: 65, count: 131_072)

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func source(hash: String? = nil, modeID: String = "mandarin-pinyin") -> LanguagePackDescriptor {
        .init(packID: "generated-fixture", version: "1", modeID: modeID, engineABI: "fixture-v1",
              sourceURL: URL(string: "https://data.example.test/" + UUID().uuidString)!, allowedHosts: ["data.example.test"],
              archiveByteCount: Int64(payload.count), archiveSHA256: hash ?? self.hash(payload),
              installedBytes: Int64(payload.count), fileCount: 1,
              files: [.init(path: "fixture.dat", byteCount: Int64(payload.count), sha256: self.hash(payload))],
              licenseNotice: "Generated fixture", sourceNotice: "Generated locally")
    }
    private func downloader(_ source: LanguagePackDescriptor) -> LanguagePackDownloader {
        LanguagePackDownloader(trustedSources: [source]) {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [LanguagePackProtocolFixture.self]
            // Must not leak injected caller headers to an upstream request.
            config.httpAdditionalHeaders = ["Authorization": "fixture", "Cookie": "fixture", "X-Fixture": "fixture"]
            return config
        }
    }
    private func scriptedDownloader(_ sources: [LanguagePackDescriptor],
                                    sleep: @escaping @Sendable (UInt64) async throws -> Void) -> LanguagePackDownloader {
        LanguagePackDownloader(trustedSources: sources, retrySleep: sleep) {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [LanguagePackProtocolFixture.self]
            config.httpAdditionalHeaders = ["Authorization": "fixture", "Cookie": "fixture", "Range": "bytes=32768-", "If-Range": "fixture"]
            return config
        }
    }

    private func script(_ source: LanguagePackDescriptor, _ fixtures: [LanguagePackProtocolFixture.Fixture]) {
        LanguagePackProtocolFixture.registerScript(source.sourceURL, fixtures: fixtures)
        addTeardownBlock { LanguagePackProtocolFixture.remove(source.sourceURL) }
    }

    private func partialFailure(beforeStart: (@Sendable (URLRequest) -> Void)? = nil,
                                afterProgress: LanguagePackPartialFailureGate? = nil) -> LanguagePackProtocolFixture.Fixture {
        .init(headers: ["Content-Length": String(payload.count)], body: Data(payload.prefix(32_768)),
              status: 200, redirect: nil, hold: false, started: nil,
              failureCode: NSURLErrorNetworkConnectionLost, beforeStart: beforeStart,
              deferFailure: { failure in
                  if let afterProgress { afterProgress.whenProgressObserved(failure) }
                  else { failure() }
              })
    }

    private func success(beforeStart: (@Sendable (URLRequest) -> Void)? = nil) -> LanguagePackProtocolFixture.Fixture {
        .init(headers: ["Content-Length": String(payload.count)], body: payload,
              status: 200, redirect: nil, hold: false, started: nil, beforeStart: beforeStart)
    }

    private static func assertFreshGET(_ request: URLRequest, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.httpMethod, "GET", file: file, line: line)
        XCTAssertNil(request.httpBody, file: file, line: line)
        for header in ["Range", "If-Range", "Authorization", "Cookie"] {
            XCTAssertNil(request.value(forHTTPHeaderField: header), header, file: file, line: line)
        }
    }

    private func install(_ source: LanguagePackDescriptor, headers: [String: String] = [:], body: Data? = nil,
                         status: Int = 200, redirect: URL? = nil, hold: Bool = false,
                         started: (@Sendable (URLRequest) -> Void)? = nil) {
        LanguagePackProtocolFixture.register(source.sourceURL, fixture: .init(headers: headers,
            body: body ?? payload, status: status, redirect: redirect, hold: hold, started: started))
        addTeardownBlock { LanguagePackProtocolFixture.remove(source.sourceURL) }
    }
    private func expect(_ expected: LanguagePackDownloadError, source: LanguagePackDescriptor,
                        file: StaticString = #filePath, line: UInt = #line) async throws {
        do {
            _ = try await downloader(source).download(source: source, scratchDirectory: scratch)
            XCTFail("Expected sanitized failure", file: file, line: line)
        } catch let error as LanguagePackDownloadError {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [], file: file, line: line)
    }

    func testTransportPartialFailureRetriesFreshGETAfterScratchCleanup() async throws {
        let source = source(), scratch = try XCTUnwrap(scratch)
        let retries = LanguagePackProgressRecorder(), delays = LanguagePackProgressRecorder()
        let fractions = LanguagePackProgressRecorder()
        let partialProgress = LanguagePackPartialFailureGate()
        script(source, [partialFailure(afterProgress: partialProgress), success(beforeStart: { request in
            Self.assertFreshGET(request)
            XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: scratch.path), [],
                           "failed attempt must not leave retained files before the next request")
        })])
        let downloader = scriptedDownloader([source], sleep: { nanoseconds in
            delays.append(Double(nanoseconds))
            XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: scratch.path), [],
                           "cleanup must finish before retry waiting starts")
        })
        let file = try await downloader.download(source: source, scratchDirectory: scratch, retrying: {
            retries.append(Double($0))
            XCTAssertTrue(fractions.values.contains { $0 > 0 && $0 < 1 },
                          "failed transfer must deliver actual partial-body progress before retry")
        }, progress: {
            fractions.append($0)
            if $0 > 0 { partialProgress.observeProgress() }
        })
        let requests = LanguagePackProtocolFixture.requests(for: source.sourceURL)
        XCTAssertEqual(requests.count, 2)
        requests.forEach { Self.assertFreshGET($0) }
        XCTAssertEqual(retries.values, [1])
        XCTAssertEqual(delays.values, [1_000_000_000])
        XCTAssertTrue(fractions.values.contains { $0 > 0 && $0 < 1 }, "real download delegate must observe body bytes")
        XCTAssertEqual(fractions.values.filter { $0 == 0 }.count, 2, "fresh attempts restart progress, not resume")
        XCTAssertEqual(fractions.values.last, 1)
        XCTAssertEqual(try Data(contentsOf: file), payload)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [file.lastPathComponent])
    }

    func testTransportCancellationAtRetryDelayBoundaryStartsNoExtraRequest() async throws {
        let source = source(), scratch = try XCTUnwrap(scratch)
        let waiting = expectation(description: "real failed transfer entered retry wait")
        let gate = LanguagePackRetryWaitGate { waiting.fulfill() }
        let delays = LanguagePackProgressRecorder()
        script(source, [partialFailure(), success(beforeStart: { _ in XCTFail("cancelled retry must not start a request") })])
        let downloader = scriptedDownloader([source], sleep: { nanoseconds in
            delays.append(Double(nanoseconds))
            // Deliberately returns normally even after cancellation. This tests
            // the cancellation boundary AFTER a delay, not just sleep throwing.
            await gate.wait()
        })
        let task = Task { try await downloader.download(source: source, scratchDirectory: scratch) }
        await fulfillment(of: [waiting], timeout: 5)
        task.cancel()
        await gate.release()
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch { XCTAssertEqual(error as? LanguagePackDownloadError, .cancelled) }
        XCTAssertEqual(delays.values, [1_000_000_000])
        XCTAssertEqual(LanguagePackProtocolFixture.requests(for: source.sourceURL).count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
    }

    func testTransportTwoSourceDownloadsShareTwoRetryBudgetAndKeepVerifiedFirstFile() async throws {
        let first = source(), second = source(), scratch = try XCTUnwrap(scratch)
        let budget = LanguagePackRetryBudget()
        let retries = LanguagePackProgressRecorder(), delays = LanguagePackProgressRecorder()
        let downloader = scriptedDownloader([first, second], sleep: { delays.append(Double($0)) })
        script(first, [partialFailure(), success()])
        let firstFile = try await downloader.download(source: first, scratchDirectory: scratch,
            retryBudget: budget, retrying: { retries.append(Double($0)) })
        let beforeSecond: @Sendable (URLRequest) -> Void = { request in
            Self.assertFreshGET(request)
            XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: scratch.path), [firstFile.lastPathComponent],
                           "failed second-source attempts must not leave partial files or delete the verified first source")
        }
        script(second, [partialFailure(beforeStart: beforeSecond), partialFailure(beforeStart: beforeSecond),
                        success(beforeStart: { _ in XCTFail("shared two-retry budget must prevent a third second-source request") })])
        do {
            _ = try await downloader.download(source: second, scratchDirectory: scratch,
                retryBudget: budget, retrying: { retries.append(Double($0)) })
            XCTFail("second source must exhaust the shared retry budget")
        } catch { XCTAssertEqual(error as? LanguagePackDownloadError, .network(code: NSURLErrorNetworkConnectionLost)) }
        let firstRequests = LanguagePackProtocolFixture.requests(for: first.sourceURL)
        let secondRequests = LanguagePackProtocolFixture.requests(for: second.sourceURL)
        XCTAssertEqual(firstRequests.count, 2)
        XCTAssertEqual(secondRequests.count, 2)
        (firstRequests + secondRequests).forEach { Self.assertFreshGET($0) }
        XCTAssertEqual(retries.values, [1, 2])
        XCTAssertEqual(delays.values, [1_000_000_000, 2_000_000_000])
        XCTAssertEqual(try Data(contentsOf: firstFile), payload)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [firstFile.lastPathComponent])
    }

    func testRetryPolicyExcludesSecurityVerificationInvalidAndStorageErrors() {
        for error in [LanguagePackDownloadError.invalidSource, .cancelled, .rejectedRedirect,
                      .verification(.sha256), .verification(.actualSize), .verification(.advertisedSize),
                      .verification(.response), .storage(operation: "test", code: 28),
                      .network(code: NSURLErrorServerCertificateUntrusted), .httpStatus(401), .httpStatus(404)] {
            XCTAssertFalse(LanguagePackDownloader.isTransient(error), "\(error)")
        }
        for error in [LanguagePackDownloadError.network(code: NSURLErrorTimedOut),
                      .network(code: NSURLErrorNetworkConnectionLost), .httpStatus(429), .httpStatus(503)] {
            XCTAssertTrue(LanguagePackDownloader.isTransient(error))
        }
    }

    func testRetriesAreBoundedAcrossFilesInOneOperationAndExposeWaitingState() async throws {
        let budget = LanguagePackRetryBudget()
        let delays = LanguagePackProgressRecorder()
        let retries = LanguagePackProgressRecorder()
        var attempts = 0
        let result: Int = try await LanguagePackDownloader.withRetries(budget: budget,
            retrying: { retries.append(Double($0)) }, sleep: { delays.append(Double($0)) }) {
                attempts += 1
                if attempts < 3 { throw LanguagePackDownloadError.httpStatus(503) }
                return 42
            }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(retries.values, [1, 2])
        XCTAssertEqual(delays.values, [1_000_000_000, 2_000_000_000])
        // Later Mandarin files share the exhausted budget: no fourth retry.
        var nextFileAttempts = 0
        do {
            let _: Int = try await LanguagePackDownloader.withRetries(budget: budget, sleep: { _ in XCTFail("budget exhausted") }) {
                nextFileAttempts += 1
                throw LanguagePackDownloadError.network(code: NSURLErrorTimedOut)
            }
            XCTFail("expected transient failure after budget exhaustion")
        } catch { XCTAssertEqual(error as? LanguagePackDownloadError, .network(code: NSURLErrorTimedOut)) }
        XCTAssertEqual(nextFileAttempts, 1)
    }

    func testNonTransientFailureNeverSleepsOrRetries() async throws {
        var attempts = 0
        do {
            let _: Int = try await LanguagePackDownloader.withRetries(budget: .init(),
                retrying: { _ in XCTFail("no verification retry") }, sleep: { _ in XCTFail("no wait") }) {
                    attempts += 1
                    throw LanguagePackDownloadError.verification(.sha256)
                }
            XCTFail("expected hash failure")
        } catch { XCTAssertEqual(error as? LanguagePackDownloadError, .verification(.sha256)) }
        XCTAssertEqual(attempts, 1)
    }

    func testCancellationDuringRetryDelayCannotStartAnotherAttempt() async throws {
        let waiting = expectation(description: "retry wait")
        let attempts = LanguagePackProgressRecorder()
        let task = Task {
            let _: Int = try await LanguagePackDownloader.withRetries(budget: .init(), sleep: { _ in
                waiting.fulfill()
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }) {
                attempts.append(1)
                throw LanguagePackDownloadError.network(code: NSURLErrorTimedOut)
            }
        }
        await fulfillment(of: [waiting], timeout: 5)
        task.cancel()
        do { try await task.value; XCTFail("expected cancellation") }
        catch { XCTAssertEqual(error as? LanguagePackDownloadError, .cancelled) }
        XCTAssertEqual(attempts.values.count, 1)
    }

    #if canImport(Uniboard) && !canImport(LanguagePackTransport)
    func testProgressGateRejectsOutOfOrderCancelledFinishedAndOldGenerationCallbacks() {
        var gate = LanguageManagementProgressGate()
        let first = UUID(), second = UUID()
        gate.begin(first)
        XCTAssertTrue(gate.accept(generation: first, sequence: 2, isActive: true, isCancelled: false))
        XCTAssertFalse(gate.accept(generation: first, sequence: 1, isActive: true, isCancelled: false))
        XCTAssertFalse(gate.accept(generation: first, sequence: 2, isActive: true, isCancelled: false))
        XCTAssertFalse(gate.accept(generation: first, sequence: 3, isActive: true, isCancelled: true))
        XCTAssertFalse(gate.accept(generation: first, sequence: 4, isActive: false, isCancelled: false))
        gate.begin(second)
        XCTAssertFalse(gate.accept(generation: first, sequence: 100, isActive: true, isCancelled: false))
        XCTAssertTrue(gate.accept(generation: second, sequence: 1, isActive: true, isCancelled: false))
    }

    func testWorkerPreflightRunsOffMainAndBlocksLowAndUnknownBeforeTouchingInstalledPack() async throws {
        // Snapshot looks up the app's persisted raw-value mode key, not the
        // arbitrary transport-only fixture key ("mandarin-pinyin").
        let descriptor = source(modeID: LanguageInputMode.mandarinPinyin.rawValue)
        let store = LanguagePackStore(root: scratch.appendingPathComponent("packs"))
        let old = try store.install(manifestData: JSONEncoder().encode(descriptor), expectedRevision: nil) {
            try self.payload.write(to: $0.appendingPathComponent("fixture.dat"))
        }
        let capacities: [Int64?] = [0, nil]
        for capacity in capacities {
            let probes = LanguagePackProgressRecorder()
            let worker = LanguageManagementWorker(root: store.root, settings: .init(directory: { nil }), capacity: { _ in
                XCTAssertFalse(Thread.isMainThread)
                probes.append(1)
                return capacity
            })
            do {
                _ = try await worker.downloadJapanese(descriptor, progress: { _ in })
                XCTFail("must not reach network/install")
            } catch let error as LanguagePackSpacePlan.SpaceError {
                switch (capacity, error) {
                case (nil, .capacityUnknown), (.some, .insufficient): break
                default: XCTFail("wrong capacity result")
                }
            }
            XCTAssertEqual(probes.values.count, 2)
            XCTAssertEqual(try store.activeRevision(modeID: descriptor.modeID), old.revision)
            XCTAssertEqual(try Data(contentsOf: old.path.appendingPathComponent("fixture.dat")), payload)
            let snapshot = await worker.snapshot()
            XCTAssertNil(snapshot.installed[.mandarinPinyin], "fixture ABI is not usable")
            XCTAssertEqual(snapshot.removable[.mandarinPinyin]?.revision, old.revision)
        }
    }
    #endif

    func testHTTPGzipUsesDecodedSizeAndHashNotCompressedContentLength() async throws {
        let source = source()
        install(source, headers: ["Content-Encoding": "gzip", "Content-Length": "163"])
        let progress = LanguagePackProgressRecorder()
        let file = try await downloader(source).download(source: source, scratchDirectory: scratch,
                                                         progress: { progress.append($0) })
        XCTAssertEqual(try Data(contentsOf: file), payload)
        let fractions = progress.values
        XCTAssertEqual(fractions.first, 0)
        XCTAssertEqual(fractions.last, 1)
        XCTAssertTrue(fractions.allSatisfy { (0...1).contains($0) })
        XCTAssertEqual(fractions, fractions.sorted())
    }

    func testEncodedMissingLengthAndNormalizedCoding() async throws {
        for coding in ["gzip", " GZip ", "deflate", "br"] {
            let source = source()
            install(source, headers: ["Content-Encoding": coding])
            let file = try await downloader(source).download(source: source, scratchDirectory: scratch)
            XCTAssertEqual(try Data(contentsOf: file), payload)
            try FileManager.default.removeItem(at: file)
        }
    }

    func testIdentityAndMissingLengthRemainSupportedAndHeadersAreIsolated() async throws {
        for headers in [[:], ["Content-Length": String(payload.count)],
                        ["Content-Encoding": "identity", "Content-Length": String(payload.count)]] {
            let source = source()
            install(source, headers: headers, started: { request in
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                XCTAssertNil(request.value(forHTTPHeaderField: "X-Fixture"))
            })
            let file = try await downloader(source).download(source: source, scratchDirectory: scratch)
            XCTAssertEqual(try Data(contentsOf: file), payload)
            try FileManager.default.removeItem(at: file)
        }
    }

    func testIdentityRejectsIncorrectAdvertisedSize() async throws {
        let source = source()
        install(source, headers: ["Content-Length": "163"])
        try await expect(.verification(.advertisedSize), source: source)
    }

    func testEncodedResponsesRejectMalformedAndExcessiveWireLengths() async throws {
        for length in ["invalid", "163, 163", "-1", "+163", "", "999999999999999999999999", String(LanguagePackDescriptor.maximumArchiveBytes + 1)] {
            let source = source()
            install(source, headers: ["Content-Encoding": "gzip", "Content-Length": length])
            try await expect(.verification(.advertisedSize), source: source)
        }
    }

    func testEncodedWireSizeIsBoundedButNotRequiredToEqualOrUndershootDecodedSize() async throws {
        let source = source()
        install(source, headers: ["Content-Encoding": "gzip", "Content-Length": String(payload.count + 100)])
        let file = try await downloader(source).download(source: source, scratchDirectory: scratch)
        XCTAssertEqual(try Data(contentsOf: file), payload)
    }

    func testGzipDecodedTruncationAndExpansionFailExactSizeAndCleanScratch() async throws {
        for body in [Data(payload.dropLast()), payload + Data([0])] {
            let source = source()
            install(source, headers: ["Content-Encoding": "gzip", "Content-Length": "163"], body: body)
            try await expect(.verification(.actualSize), source: source)
        }
    }

    func testGzipCorrectDecodedSizeStillRequiresPinnedSHA() async throws {
        let source = source(hash: String(repeating: "0", count: 64))
        install(source, headers: ["Content-Encoding": "gzip", "Content-Length": "163"])
        try await expect(.verification(.sha256), source: source)
    }

    func testUnsupportedContentCodingIsRejected() async throws {
        for coding in ["unknown", "gzip, br", "", "identity, gzip"] {
            let source = source()
            install(source, headers: ["Content-Encoding": coding, "Content-Length": "163"])
            try await expect(.verification(.response), source: source)
        }
    }

    func testStatusIsSanitizedAndRejectedBeforeBody() async throws {
        let source = source()
        install(source, headers: ["Content-Length": "1"], status: 503)
        try await expect(.httpStatus(503), source: source)
    }

    func testForeignAndInsecureRedirectsAreRejected() async throws {
        for address in ["https://foreign.example.test/fixture", "http://data.example.test/fixture"] {
            let source = source()
            install(source, redirect: URL(string: address)!)
            try await expect(.rejectedRedirect, source: source)
        }
    }

    func testSameHostRedirectRebuildsRequestWithoutServerSuppliedHeaders() async throws {
        let source = source()
        let destination = URL(string: "https://data.example.test/" + UUID().uuidString)!
        install(source, redirect: destination)
        LanguagePackProtocolFixture.register(destination, fixture: .init(
            headers: ["Content-Encoding": "gzip", "Content-Length": "163"], body: payload,
            status: 200, redirect: nil, hold: false, started: { request in
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            }))
        addTeardownBlock { LanguagePackProtocolFixture.remove(destination) }
        let file = try await downloader(source).download(source: source, scratchDirectory: scratch)
        XCTAssertEqual(try Data(contentsOf: file), payload)
    }

    func testUnregisteredSourceCannotStartTransfer() async throws {
        let source = source()
        install(source, started: { _ in XCTFail("Must not make an untrusted request") })
        do {
            _ = try await LanguagePackDownloader(trustedSources: []).download(source: source, scratchDirectory: scratch)
            XCTFail("Expected invalid source")
        } catch let error as LanguagePackDownloadError { XCTAssertEqual(error, .invalidSource) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
    }

    func testCancellationDeletesPartiallyWrittenDecodedBody() async throws {
        // The first URLSession use in a cold app-hosted simulator may spend tens
        // of seconds initializing Foundation services, before any URLProtocol
        // request exists. Prime through a real verified transfer OUTSIDE the
        // cancellation scenario; do not confuse setup latency with cancellation
        // of a partially written body. No real network or unverified file is used.
        let warmupSource = source()
        install(warmupSource)
        let warmupFile = try await downloader(warmupSource).download(source: warmupSource, scratchDirectory: scratch)
        XCTAssertEqual(try Data(contentsOf: warmupFile), payload)
        try FileManager.default.removeItem(at: warmupFile)

        let source = source()
        let written = expectation(description: "download delegate observed partial decoded body")
        let finished = expectation(description: "active transfer promptly completed cancellation")
        let partialProgress = LanguagePackPartialFailureGate()
        let fractions = LanguagePackProgressRecorder()
        partialProgress.whenProgressObserved { written.fulfill() }
        install(source, headers: ["Content-Encoding": "gzip", "Content-Length": "163"], hold: true)
        let task = Task {
            defer { finished.fulfill() }
            return try await downloader(source).download(source: source, scratchDirectory: scratch, progress: {
                fractions.append($0)
                if $0 > 0 { partialProgress.observeProgress() }
            })
        }
        // Both bounds apply after the separate verified initialization transfer.
        // The held fixture cannot finish successfully while this test waits.
        await fulfillment(of: [written], timeout: 5)
        task.cancel()
        await fulfillment(of: [finished], timeout: 5)
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch let error as LanguagePackDownloadError { XCTAssertEqual(error, .cancelled) }
        XCTAssertTrue(fractions.values.contains { $0 > 0 && $0 < 1 })
        XCTAssertFalse(fractions.values.contains(1), "cancelled partial transfer must never report verified completion")
        XCTAssertEqual(LanguagePackProtocolFixture.requests(for: source.sourceURL).count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
    }

    func testPreCancelledTaskDoesNotStartRequest() async throws {
        let source = source()
        install(source, started: { _ in XCTFail("Pre-cancelled transfer must not start") })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await downloader(source).download(source: source, scratchDirectory: scratch)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch let error as LanguagePackDownloadError { XCTAssertEqual(error, .cancelled) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
    }
}

private final class LanguagePackProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double] = []
    func append(_ fraction: Double) { lock.lock(); defer { lock.unlock() }; fractions.append(fraction) }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return fractions }
}

/// A protocol client can batch a synchronous body+error burst and suppress
/// download progress. Fail only once BOTH body delivery and a real didWriteData
/// callback occurred; no timing sleeps and no mocked transport attempt.
private final class LanguagePackPartialFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var progressObserved = false
    private var pendingFailure: (@Sendable () -> Void)?
    func whenProgressObserved(_ failure: @escaping @Sendable () -> Void) {
        lock.lock()
        if progressObserved { lock.unlock(); failure() }
        else { pendingFailure = failure; lock.unlock() }
    }
    func observeProgress() {
        lock.lock()
        progressObserved = true
        let failure = pendingFailure
        pendingFailure = nil
        lock.unlock()
        failure?()
    }
}

/// Intentionally cancellation-unaware delay: release models the race where a
/// timer fires normally just as its parent operation is cancelled.
private actor LanguagePackRetryWaitGate {
    private let onWaiting: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(onWaiting: @escaping @Sendable () -> Void) { self.onWaiting = onWaiting }
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onWaiting()
        }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class LanguagePackProtocolFixture: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable {
        var headers: [String: String]
        var body: Data
        var status: Int
        var redirect: URL?
        var hold: Bool
        var started: (@Sendable (URLRequest) -> Void)?
        var failureCode: Int? = nil
        var beforeStart: (@Sendable (URLRequest) -> Void)? = nil
        var deferFailure: (@Sendable (@escaping @Sendable () -> Void) -> Void)? = nil
    }
    private struct Script {
        let fixtures: [Fixture]
        let repeatsLast: Bool
        var next = 0
        var requests: [URLRequest] = []
    }
    private static let lock = NSLock()
    private static var scripts: [URL: Script] = [:]
    static func register(_ url: URL, fixture: Fixture) {
        lock.lock(); defer { lock.unlock() }
        scripts[url] = Script(fixtures: [fixture], repeatsLast: true)
    }
    static func registerScript(_ url: URL, fixtures: [Fixture]) {
        lock.lock(); defer { lock.unlock() }
        scripts[url] = Script(fixtures: fixtures, repeatsLast: false)
    }
    static func remove(_ url: URL) { lock.lock(); defer { lock.unlock() }; scripts[url] = nil }
    static func requests(for url: URL) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return scripts[url]?.requests ?? []
    }
    private static func fixture(for request: URLRequest) -> Fixture? {
        lock.lock(); defer { lock.unlock() }
        guard let url = request.url, var script = scripts[url] else { return nil }
        script.requests.append(request)
        let index = script.repeatsLast ? min(script.next, script.fixtures.count - 1) : script.next
        script.next += 1
        scripts[url] = script
        guard script.fixtures.indices.contains(index) else { return nil }
        return script.fixtures[index]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let fixture = Self.fixture(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        fixture.beforeStart?(request)
        if let redirect = fixture.redirect {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirect.absoluteString])!
            var request = URLRequest(url: redirect)
            request.setValue("fixture", forHTTPHeaderField: "Authorization")
            request.setValue("fixture", forHTTPHeaderField: "Cookie")
            client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: "HTTP/1.1", headerFields: fixture.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = fixture.hold ? Data(fixture.body.prefix(32_768)) : fixture.body
        for offset in stride(from: 0, to: body.count, by: 4096) {
            client?.urlProtocol(self, didLoad: body.subdata(in: offset..<min(offset + 4096, body.count)))
        }
        fixture.started?(request)
        if let code = fixture.failureCode {
            let failure: @Sendable () -> Void = { [self] in
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: code))
            }
            if let deferFailure = fixture.deferFailure { deferFailure(failure) }
            else { failure() }
        } else if !fixture.hold { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}
#endif
