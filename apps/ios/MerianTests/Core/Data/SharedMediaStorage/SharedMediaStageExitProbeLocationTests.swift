import Darwin
import Foundation
import XCTest

final class SharedMediaStageExitProbeLocationTests: XCTestCase {
    typealias Locations = SharedMediaStageExitProbeLocation

    private func fixture() throws -> (base: URL, data: URL, nonce: UUID) {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("stage-location-" + UUID().uuidString)
        let data = base.appendingPathComponent("data"), nonce = UUID()
        try FileManager.default.createDirectory(at: data.appendingPathComponent(Locations.components(nonce).last!),
            withIntermediateDirectories: true)
        return (base, data, nonce)
    }

    func testRenamePreservesPhysicalRoot() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let before = try Locations.capture(data: f.data, nonce: f.nonce)
        let held = try SharedMediaStageExitProbeSupport.directory(f.data)
        defer { close(held) }
        let moved = f.base.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: f.data, to: moved)
        let after = try Locations.capture(data: moved, nonce: f.nonce)
        XCTAssertNotEqual(before.dataPath, after.dataPath)
        try after.requireSamePhysicalRoot(as: before)
        var info = stat()
        XCTAssertEqual(fstat(held, &info), 0)
        XCTAssertEqual(after.bindings[""]?.inode, UInt64(info.st_ino))
    }

    func testCopiedTreeRejectsMatchingContents() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let record = f.data.appendingPathComponent(Locations.components(f.nonce).last!).appendingPathComponent("record")
        try Data("same synthetic bytes".utf8).write(to: record)
        let before = try Locations.capture(data: f.data, nonce: f.nonce)
        let copy = f.base.appendingPathComponent("copy")
        try FileManager.default.copyItem(at: f.data, to: copy)
        XCTAssertEqual(try Data(contentsOf: record), try Data(contentsOf:
            copy.appendingPathComponent(Locations.components(f.nonce).last!).appendingPathComponent("record")))
        XCTAssertThrowsError(try Locations.capture(data: copy, nonce: f.nonce).requireSamePhysicalRoot(as: before))
    }

    func testTraversalAndSymlinkRejected() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        for path in ["", "/absolute", "../outside", "Library/../tmp", "Library//Caches", "./Library", "Library/", "a\0b"] {
            XCTAssertThrowsError(try Locations.resolve(path, below: f.data), path)
        }
        let alias = f.base.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.data)
        XCTAssertThrowsError(try Locations.capture(data: alias, nonce: f.nonce))
        let caches = f.data.appendingPathComponent("Library/Caches")
        let moved = f.base.appendingPathComponent("moved-caches")
        try FileManager.default.moveItem(at: caches, to: moved)
        try FileManager.default.createSymbolicLink(at: caches, withDestinationURL: moved)
        XCTAssertThrowsError(try Locations.capture(data: f.data, nonce: f.nonce))
    }

    func testPublicationPreservesIdentityButUnlinkedDirectoriesFail() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let before = try Locations.capture(data: f.data, nonce: f.nonce)
        let relative = try XCTUnwrap(Locations.components(f.nonce).last)
        let root = f.data.appendingPathComponent(relative)
        let held = try SharedMediaStageExitProbeSupport.directory(root)
        defer { close(held) }
        let record = root.appendingPathComponent("anchor.json")
        try Data("synthetic publication".utf8).write(to: record)
        let after = try Locations.capture(data: f.data, nonce: f.nonce)
        try after.requireSamePhysicalRoot(as: before)
        let identity = try XCTUnwrap(after.bindings[relative])
        XCTAssertTrue(identity.matchesPhysicalIdentity(.init(device: identity.device, inode: identity.inode,
            kind: identity.kind, links: identity.links + 1)))
        XCTAssertFalse(identity.matchesPhysicalIdentity(.init(device: identity.device, inode: identity.inode,
            kind: identity.kind, links: 0)))
        try FileManager.default.removeItem(at: record)
        try FileManager.default.removeItem(at: root)
        var info = stat()
        XCTAssertEqual(fstat(held, &info), 0)
        // An open descriptor may retain a positive link count after its name is removed.
        // Named-entry continuity comes from fresh no-follow capture, not that count.
        XCTAssertEqual(UInt64(info.st_dev), identity.device)
        XCTAssertEqual(UInt64(info.st_ino), identity.inode)
        XCTAssertEqual(UInt32(info.st_mode & S_IFMT), identity.kind)
        XCTAssertThrowsError(try Locations.capture(data: f.data, nonce: f.nonce))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("synthetic publication".utf8).write(to: record)
        let replacement = try Locations.capture(data: f.data, nonce: f.nonce)
        XCTAssertEqual(replacement.dataPath, before.dataPath)
        XCTAssertEqual(try Data(contentsOf: record), Data("synthetic publication".utf8))
        XCTAssertNotEqual(replacement.bindings[relative]?.inode, identity.inode)
        XCTAssertThrowsError(try replacement.requireSamePhysicalRoot(as: before))
    }

    @MainActor
    func testIdenticalStoreReplacementRejected() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.base) }
        let store = f.data.appendingPathComponent("tmp/native-app-metadata-" + UUID().uuidString + "/database/ledger.store")
        let control = f.data.appendingPathComponent("Library/Application Support/native-app-metadata-" + UUID().uuidString + "/control")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        let bytes = Data("synthetic unchanged store UUID and contents".utf8)
        try bytes.write(to: store)
        let before = try SharedMediaStageExitProbeRecords.physical(store: store, control: control, data: f.data)
        let held = open(store.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(held, 0)
        guard held >= 0 else { return }
        defer { close(held) }
        try FileManager.default.removeItem(at: store)
        try bytes.write(to: store)
        XCTAssertEqual(try Data(contentsOf: store), bytes)
        let after = try SharedMediaStageExitProbeRecords.physical(store: store, control: control, data: f.data)
        XCTAssertEqual(before.filter { $0.key != "store" }, after.filter { $0.key != "store" })
        XCTAssertNotEqual(before["store"], after["store"])
        XCTAssertThrowsError(try Locations.requireSameBindings(after, before))
        let single = try XCTUnwrap(after["store"])
        XCTAssertFalse(single.matchesPhysicalIdentity(.init(device: single.device, inode: single.inode,
            kind: single.kind, links: 2)))
    }
}
