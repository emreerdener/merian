import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisCleanupTests {
    let fixture = ObservationReanalysisPersistenceTests()

    func receipt(_ container: ModelContainer) throws -> ObservationReanalysisErasureReceipt {
        _ = try fixture.stage(container)
        let context = ModelContext(container)
        _ = try ObservationReanalysisErasure.removeChildren(of: fixture.fixture.observation.uuidString, context: context)
        try context.save()
        return .init(parentID: fixture.fixture.observation, childID: fixture.child)
    }

    func write(_ root: URL, child: UUID) throws -> URL {
        let directory = root.appendingPathComponent("ReanalysisQueue/" + child.uuidString.lowercased())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("photo.jpg"))
        try Data([4]).write(to: directory.appendingPathComponent(".interrupted.preparing"))
        return directory
    }

    func status(_ container: ModelContainer) throws -> OfflineJobStatus {
        let job = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(fixture.child)))
        return job.status
    }

    @Test func restartedOwnerErasesWholeNamespaceAndRetainsMinimalTombstone() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID), sibling = try write(root, child: UUID())
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: root))
        await owner.drain(container: container, isCurrent: { true })
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sibling.path).count == 2)
        #expect(try status(container) == .complete)
        #expect(throws: (any Error).self) { try fixture.stage(container) }
        // Completed receipts never cause a later object to be erased.
        try Data([9]).write(to: child.appendingPathComponent("replacement.jpg"))
        await ObservationReanalysisErasureOwner(files: .init(documents: root)).drain(container: container, isCurrent: { true })
        #expect(try Data(contentsOf: child.appendingPathComponent("replacement.jpg")) == Data([9]))
    }

    @Test func failedLocalCleanupRetainsReceiptAndLaterOpportunityRetries() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID)
        let unexpected = child.appendingPathComponent("unexpected-directory")
        try FileManager.default.createDirectory(at: unexpected, withIntermediateDirectories: false)
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: root))
        await owner.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .pending)
        try FileManager.default.removeItem(at: unexpected)
        await owner.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .complete)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
    }

    @Test func failedAcknowledgmentAfterErasureRecoversFromEmptyDirectory() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID), files = ObservationReanalysisFileStore(documents: root)
        await #expect(throws: (any Error).self) {
            try await files.erase(child: expected.childID, authorize: {
                try ObservationReanalysisErasurePersistence.validate(expected, container: container, isCurrent: { true })
            }, acknowledge: {
                _ = try ObservationReanalysisErasurePersistence.validate(expected, container: container, isCurrent: { true }, complete: true,
                    save: { _ in throw CocoaError(.fileWriteUnknown) })
            })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try status(container) == .pending)
        await ObservationReanalysisErasureOwner(files: files).drain(container: container, isCurrent: { true })
        #expect(try status(container) == .complete)
    }

    @Test func survivingChildAndChangedContainerNeverAuthorizeErasure() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID)
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: root))
        await owner.drain(container: container, isCurrent: { false })
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).count == 2)
        let context = ModelContext(container)
        context.insert(OfflineQueuedScan(id: expected.childID.uuidString.lowercased())); try context.save()
        await owner.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .pending)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).count == 2)
    }

    @Test func sharedChildLockAndExclusiveRootLockFenceCleanup() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let childID = UUID(), child = try write(root, child: childID)
        for url in [child, root] {
            let descriptor = open(url.path, O_RDONLY | O_DIRECTORY)
            defer { close(descriptor) }
            #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
            await #expect(throws: ObservationReanalysisFileStore.Failure.busy) {
                try await ObservationReanalysisFileStore(documents: root).erase(child: childID,
                    authorize: { Issue.record("Lock was bypassed"); return true }, acknowledge: {})
            }
            #expect(flock(descriptor, LOCK_UN) == 0)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).count == 2)
    }

    @Test func childSymlinkIsRejectedAndFileSymlinkNeverFollowsDestination() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory(), outside = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("private.jpg"); try Data([8]).write(to: target)
        let childID = UUID(), child = try write(root, child: childID)
        try FileManager.default.createSymbolicLink(at: child.appendingPathComponent("link.jpg"), withDestinationURL: target)
        try await ObservationReanalysisFileStore(documents: root).erase(child: childID, authorize: { true }, acknowledge: {})
        #expect(try Data(contentsOf: target) == Data([8]))
        try FileManager.default.removeItem(at: child)
        try FileManager.default.createSymbolicLink(at: child, withDestinationURL: outside)
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisFileStore(documents: root).erase(child: childID, authorize: { true }, acknowledge: {})
        }
        #expect(try Data(contentsOf: target) == Data([8]))
    }

    @Test func namespaceReplacementCannotBeAcknowledgedAsClean() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let childID = UUID(), child = try write(root, child: childID)
        await #expect(throws: ObservationReanalysisFileStore.Failure.cleanupFailed) {
            try await ObservationReanalysisFileStore(documents: root).erase(child: childID, authorize: {
                try FileManager.default.moveItem(at: child, to: root.appendingPathComponent("detached"))
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
                try Data([9]).write(to: child.appendingPathComponent("replacement.jpg"))
                return true
            }, acknowledge: { Issue.record("Replacement namespace was incorrectly acknowledged") })
        }
        #expect(try Data(contentsOf: child.appendingPathComponent("replacement.jpg")) == Data([9]))
    }

    @Test func malformedFirstPageCannotStarveLaterValidReceipt() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container), context = ModelContext(container)
        for index in 0..<65 {
            context.insert(OfflineJobRecord(id: String(format: "000-invalid-%03d", index), kind: .observationReanalysisErasure,
                status: .pending, metadataJSON: "invalid"))
        }
        try context.save()
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID)
        await ObservationReanalysisErasureOwner(files: .init(documents: root)).drain(container: container, isCurrent: { true })
        #expect(try status(container) == .complete)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 66)
    }
}
