import Foundation
import XCTest
@testable import Merian

/// Safe transport checks only. No store construction, abrupt exit or provider.
final class SharedMediaStageProbeTransportTests: XCTestCase {
    private typealias Probe = SharedMediaStageExitProbeSupport
    private let nonce = UUID(uuidString: "01234567-89ab-4cde-8fab-0123456789ab")!

    private func environment() -> [String: String] {
        ["NONCE": nonce.uuidString.lowercased(), "PHASE": "handshake", "SELECTOR": Probe.handshakeSelector,
         "CANDIDATE": String(repeating: "a", count: 64), "APP_SHA256": String(repeating: "b", count: 64),
         "TEST_SHA256": String(repeating: "c", count: 64)].reduce(into: [:]) { $0[Probe.prefix + $1.key] = $1.value }
    }

    func testUnarmedInvocationHasNoTicket() throws {
        XCTAssertNil(try Probe.ticket(environment: [:], selector: Probe.handshakeSelector, phase: "handshake"))
        XCTAssertNil(try Probe.ticket(environment: ["UNRELATED": "value"], selector: Probe.handshakeSelector, phase: "handshake"))
    }

    func testEveryInvocationFieldIsRequiredAndBound() throws {
        let expected = try XCTUnwrap(Probe.ticket(environment: environment(), selector: Probe.handshakeSelector, phase: "handshake"))
        XCTAssertEqual(expected.nonce, nonce)
        for key in environment().keys {
            var missing = environment(); missing.removeValue(forKey: key)
            XCTAssertThrowsError(try Probe.ticket(environment: missing, selector: Probe.handshakeSelector, phase: "handshake"))
            var different = environment(); different[key] = "wrong"
            XCTAssertThrowsError(try Probe.ticket(environment: different, selector: Probe.handshakeSelector, phase: "handshake"))
        }
        XCTAssertThrowsError(try Probe.ticket(environment: environment(), selector: Probe.childSelector, phase: "handshake"))
        var forged = environment(); forged[Probe.prefix + "SELECTOR"] = "unreviewed"
        XCTAssertThrowsError(try Probe.ticket(environment: forged, selector: "unreviewed", phase: "handshake"))
        var uppercase = environment(); uppercase[Probe.prefix + "NONCE"] = nonce.uuidString
        XCTAssertThrowsError(try Probe.ticket(environment: uppercase, selector: Probe.handshakeSelector, phase: "handshake"))
    }

    func testExclusiveMarkerCannotBeReplacedOrConsumedTwice() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ticket = try XCTUnwrap(Probe.ticket(environment: environment(), selector: Probe.handshakeSelector, phase: "handshake"))
        try Probe.create(ticket, name: "attempt.json", root: root)
        let bytes = try Data(contentsOf: root.appendingPathComponent("attempt.json"))
        XCTAssertThrowsError(try Probe.create(ticket, name: "attempt.json", root: root)) { error in
            guard case Probe.Failure.consumed = error else { return XCTFail("Expected consumed attempt") }
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("attempt.json")), bytes)
        XCTAssertEqual(try Probe.read(Probe.Ticket.self, name: "attempt.json", root: root), ticket)
    }

    func testInvalidNamesLinksAndOversizedRecordsFailClosed() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ticket = try XCTUnwrap(Probe.ticket(environment: environment(), selector: Probe.handshakeSelector, phase: "handshake"))
        for name in ["", ".", "..", "../escape", "a/b", "bad\0name"] {
            XCTAssertThrowsError(try Probe.create(ticket, name: name, root: root))
            XCTAssertThrowsError(try Probe.read(Probe.Ticket.self, name: name, root: root))
        }
        try Probe.create(ticket, name: "valid.json", root: root)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link.json").path, withDestinationPath: "valid.json")
        XCTAssertThrowsError(try Probe.read(Probe.Ticket.self, name: "link.json", root: root))
        try FileManager.default.linkItem(at: root.appendingPathComponent("valid.json"), to: root.appendingPathComponent("hard.json"))
        XCTAssertThrowsError(try Probe.read(Probe.Ticket.self, name: "hard.json", root: root))
        try Data(repeating: 0, count: 1_048_577).write(to: root.appendingPathComponent("oversized.json"))
        XCTAssertThrowsError(try Probe.read(Probe.Ticket.self, name: "oversized.json", root: root))
        XCTAssertThrowsError(try Probe.create(String(repeating: "a", count: 1_048_576), name: "large.json", root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("large.json").path))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("directory-link").path, withDestinationPath: root.path)
        XCTAssertThrowsError(try Probe.read(Probe.Ticket.self, name: "valid.json", root: root.appendingPathComponent("directory-link")))
    }

    func testNoncanonicalOrUnknownTicketFieldsAreRejected() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ticket = try XCTUnwrap(Probe.ticket(environment: environment(), selector: Probe.handshakeSelector, phase: "handshake"))
        let data = try SharedMediaNativeDraftEnvelope.bytes(ticket)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["unknown"] = true
        try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(to: root.appendingPathComponent("unknown.json"))
        XCTAssertThrowsError(try Probe.read(Probe.Ticket.self, name: "unknown.json", root: root))
        try (data + Data("\n".utf8)).write(to: root.appendingPathComponent("whitespace.json"))
        XCTAssertThrowsError(try Probe.read(Probe.Ticket.self, name: "whitespace.json", root: root))
    }

    /// Fixed host-produced bytes, not bytes synthesized by the encoder under test.
    /// Synthetic identities prove codec compatibility only, never filesystem ownership.
    func testHostCanonicalAnchorRoundTripAndRawSlashRejection() throws {
        typealias Locations = SharedMediaStageExitProbeLocation
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let golden = Data(#"{"location":{"bindings":{"":{"device":1,"inode":100,"kind":16384,"links":2},"Library":{"device":1,"inode":101,"kind":16384,"links":2},"Library\/Caches":{"device":1,"inode":102,"kind":16384,"links":2},"Library\/Caches\/merian-stage-exit-probes":{"device":1,"inode":103,"kind":16384,"links":2},"Library\/Caches\/merian-stage-exit-probes\/01234567-89ab-4cde-8fab-0123456789ab":{"device":1,"inode":104,"kind":16384,"links":2}},"bundle":"app.merian.Merian","dataPath":"\/fixture\/data","nonce":"01234567-89AB-4CDE-8FAB-0123456789AB"},"ticket":{"appSHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","candidate":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","nonce":"01234567-89AB-4CDE-8FAB-0123456789AB","testSHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","version":1}}"#.utf8)
        try golden.write(to: root.appendingPathComponent("host-anchor.json"))
        let anchor = try Probe.read(Locations.Anchor.self, name: "host-anchor.json", root: root)
        XCTAssertEqual(anchor.ticket.nonce, nonce)
        XCTAssertEqual(anchor.location.dataPath, "/fixture/data")
        XCTAssertEqual(anchor.location.bindings["Library/Caches"]?.inode, 102)
        XCTAssertEqual(Set(anchor.location.bindings.keys), Set(Locations.components(nonce)))
        try Probe.create(anchor, name: "native-anchor.json", root: root)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("native-anchor.json")), golden)
        let rawSlashes = Data(String(decoding: golden, as: UTF8.self)
            .replacingOccurrences(of: #"\/"#, with: "/").utf8)
        XCTAssertNotEqual(rawSlashes, golden)
        try rawSlashes.write(to: root.appendingPathComponent("raw-anchor.json"))
        XCTAssertThrowsError(try Probe.read(Locations.Anchor.self, name: "raw-anchor.json", root: root))
    }

    func testStreamingDigestAndMissingRoot() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 0x5a, count: 2_097_153), file = root.appendingPathComponent("binary")
        try bytes.write(to: file)
        XCTAssertEqual(try Probe.digest(file), SharedMediaAcquisitionEncoding.digest(bytes))
        XCTAssertThrowsError(try Probe.create("value", name: "record.json", root: root.appendingPathComponent("missing")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing").path))
    }

    /// Selected separately with exact per-invocation environment and ticket.
    /// This handshake proves transport only; it cannot arm an abrupt exit.
    func testInvocationHandshake() throws {
        guard let invocation = try Probe.invocation(selector: Probe.handshakeSelector, phase: "handshake", testBundle: Bundle(for: Self.self)) else { return }
        let ticket = try Probe.read(Probe.Ticket.self, name: "ticket.json", root: invocation.root)
        guard ticket == invocation.ticket else { throw Probe.Failure.invalid }
        try Probe.create(ticket, name: "handshake.json", root: invocation.root)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("stage-transport-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }
}
