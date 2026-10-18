#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardDocumentIdentityTests: XCTestCase {
    private final class UUIDSource: NSObject {
        var identifier: NSUUID?
        var reads = 0
        init(_ identifier: NSUUID?) { self.identifier = identifier }
        @objc var documentIdentifier: NSUUID? { reads += 1; return identifier }
    }
    private final class WrongSource: NSObject {
        @objc var documentIdentifier: NSString { "not an NSUUID" }
    }
    private final class UnavailableSource: NSObject {
        var invoked = false
        @objc var documentIdentifier: NSUUID? { invoked = true; return NSUUID() }
        override func responds(to selector: Selector!) -> Bool {
            if NSStringFromSelector(selector) == "documentIdentifier" { return false }
            return super.responds(to: selector)
        }
    }

    func testNilSourceAndMissingPublicGetterReturnNoIdentity() {
        XCTAssertNil(KeyboardDocumentIdentity.read(from: nil))
        XCTAssertNil(KeyboardDocumentIdentity.read(from: NSObject()))
    }
    func testObjectiveCNilIsPreservedWithoutCallingTheNonnullSwiftUUIDBridge() {
        let source = UUIDSource(nil)
        XCTAssertNil(KeyboardDocumentIdentity.read(from: source))
        XCTAssertEqual(source.reads, 1)
    }
    func testWrongObjectTypeIsRejectedInsteadOfParsingOrFabricatingAnIdentity() {
        XCTAssertNil(KeyboardDocumentIdentity.read(from: WrongSource()))
        XCTAssertNil(KeyboardDocumentIdentity.read(from: NSString(string: UUID().uuidString)))
    }
    func testRealNSUUIDMatchesExactlyAndIsReadOncePerCheck() {
        let expected = UUID(), source = UUIDSource(nil)
        source.identifier = expected as NSUUID
        XCTAssertEqual(KeyboardDocumentIdentity.read(from: source), expected)
        XCTAssertEqual(source.reads, 1)
    }
    func testConnectionLifecycleDoesNotCacheStaleIdentityAcrossNilOrDocumentReplacement() {
        let first = UUID(), second = UUID(), source = UUIDSource(nil)
        XCTAssertNil(KeyboardDocumentIdentity.read(from: source))
        source.identifier = first as NSUUID
        XCTAssertEqual(KeyboardDocumentIdentity.read(from: source), first)
        source.identifier = nil
        XCTAssertNil(KeyboardDocumentIdentity.read(from: source))
        source.identifier = second as NSUUID
        XCTAssertEqual(KeyboardDocumentIdentity.read(from: source), second)
        XCTAssertEqual(source.reads, 4)
    }
    func testGetterWhichReportsUnavailableIsNotInvoked() {
        let source = UnavailableSource()
        XCTAssertNil(KeyboardDocumentIdentity.read(from: source))
        XCTAssertFalse(source.invoked)
    }
}
#endif
