import Foundation
@testable import Merian
import XCTest

@MainActor
final class StartupStoreFenceTests: XCTestCase {
    func testCreatesOnlyAnchoredParentsAndRetainsExclusiveOwnership() throws {
        let root = try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Library/Support/default.store")
        var fence: SharedMediaStoreReadFence? = try SharedMediaStoreReadFence(
            store: store, access: .sharedWriter, creationAnchor: root
        )
        let binding = try XCTUnwrap(fence).binding()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        XCTAssertThrowsError(try SharedMediaStoreReadFence(store: store, access: .sharedWriter))
        XCTAssertThrowsError(try SharedMediaStoreReadFence(store: store))
        fence = nil
        let reopened = try SharedMediaStoreReadFence(store: store, access: .sharedWriter)
        XCTAssertEqual(try reopened.binding(), binding)
        let control = store.deletingLastPathComponent().appendingPathComponent(SharedMediaStoreReadFence.name)
        XCTAssertEqual(try Data(contentsOf: control).count, 0)
    }

    func testInterruptedParentCreationIsReestablishedByFreshOwner() throws {
        let root = try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Library/Support/default.store")
        XCTAssertThrowsError(try SharedMediaStoreReadFence(
            store: store, access: .sharedWriter, creationAnchor: root,
            synchronization: .init(failing: .parent)
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.deletingLastPathComponent().path))
        let fresh = try SharedMediaStoreReadFence(store: store, access: .sharedWriter, creationAnchor: root)
        try fresh.check()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
    }

    func testOrdinaryOwnerDoesNotCreateMissingParents() throws {
        let root = try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("missing")
        XCTAssertThrowsError(try SharedMediaStoreReadFence(store: parent.appendingPathComponent("default.store")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path))
    }

    func testRejectsEscapingSymlinkAndWrongTypeParents() throws {
        let root = try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
        let outside = try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        XCTAssertThrowsError(try SharedMediaStoreReadFence(
            store: outside.appendingPathComponent("no-create/default.store"),
            access: .sharedWriter, creationAnchor: root
        ))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try SharedMediaStoreReadFence(
            store: link.appendingPathComponent("no-create/default.store"),
            access: .sharedWriter, creationAnchor: root
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("no-create").path))
        let file = root.appendingPathComponent("file")
        try Data([1]).write(to: file)
        XCTAssertThrowsError(try SharedMediaStoreReadFence(
            store: file.appendingPathComponent("default.store"), access: .sharedWriter, creationAnchor: root
        ))
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
    }

    func testReplacementInvalidatesHeldOwnerWithoutReacquisition() throws {
        let root = try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("store")
        let store = parent.appendingPathComponent("default.store")
        let fence = try SharedMediaStoreReadFence(store: store, access: .sharedWriter, creationAnchor: root)
        try FileManager.default.moveItem(at: parent, to: root.appendingPathComponent("retained"))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        XCTAssertThrowsError(try fence.check())
        XCTAssertThrowsError(try fence.binding())
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent(SharedMediaStoreReadFence.name).path))
    }

    func testSynchronizationFailurePreservesStoreAndAllowsLaterFreshOwner() throws {
        for stage in [SharedMediaFenceSyncStage.file, .parent] {
            let root = try StoreRecoveryTestSupport.makeTempDirectory().resolvingSymlinksInPath()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("default.store")
            try Data([2, 3]).write(to: store)
            XCTAssertThrowsError(try SharedMediaStoreReadFence(
                store: store, access: .sharedWriter, creationAnchor: root,
                synchronization: .init(failing: stage)
            ))
            XCTAssertEqual(try Data(contentsOf: store), Data([2, 3]))
            let fresh = try SharedMediaStoreReadFence(store: store, access: .sharedWriter, creationAnchor: root)
            try fresh.check()
        }
    }
}
