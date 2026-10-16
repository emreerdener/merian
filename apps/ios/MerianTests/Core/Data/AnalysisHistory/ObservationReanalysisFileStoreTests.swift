import CryptoKit
import Darwin
import Foundation
@testable import Merian
import Testing

@MainActor
@Suite(.serialized)
struct ObservationReanalysisFileStoreTests {
    enum Rejected: Error { case commit }
    let fixture = ObservationReanalysisPersistenceTests()
    func draft() throws -> ObservationReanalysisDraft {
        let intent = try fixture.intent()
        return try .init(identity: intent.identity, evidence: intent.request.evidence)
    }
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test func uploadReadPreservesOrderedBytesAndHoldsLocksThroughFinalValidation() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try ObservationReanalysisProducerTests().image()
        let identity = try draft().identity
        let refs = [UUID(), UUID()].map { ObservationEvidenceUpload.Reference(mediaID: $0, contentType: "image/png",
            byteCount: bytes.count, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()) }
        let draft = try ObservationReanalysisDraft(identity: identity,
            evidence: [.image(refs[1]), .description("Between photos"), .image(refs[0])])
        let store = ObservationReanalysisFileStore(documents: root)
        try await store.persist(draft: draft, photos: [bytes, bytes]) {}
        var boundaries = 0
        let validate: @MainActor @Sendable () throws -> Void = {
            boundaries += 1
            let child = root.appendingPathComponent("ReanalysisQueue/" + identity.analysisID.uuidString.lowercased())
            for url in [root, child] {
                let descriptor = open(url.path, O_RDONLY | O_DIRECTORY)
                #expect(descriptor >= 0); defer { close(descriptor) }
                #expect(flock(descriptor, LOCK_EX | LOCK_NB) != 0)
            }
        }
        let photos = try await store.readPhotos(draft: draft, validateBeforeRead: validate, validateBeforeReturn: validate)
        #expect(boundaries == 2 && photos.map(\.mediaID) == [refs[1].mediaID, refs[0].mediaID])
        #expect(photos.allSatisfy { $0.bytes == bytes && $0.contentType == "image/png" })
        let upload = try ObservationEvidenceUpload(observationID: identity.observationID, analysisID: identity.analysisID, photos: photos).prepare()
        #expect(upload.references == [refs[1], refs[0]])
    }

    @Test(arguments: [false, true])
    func uploadReadWithholdsAllBytesWhenEitherAuthorizationBoundaryFails(failAfterRead: Bool) async throws {
        let seed = try ObservationReanalysisRecoveryTests().seed()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        try await ObservationReanalysisRecoveryTests().publish(seed)
        let store = ObservationReanalysisFileStore(documents: seed.root)
        var reachedFinal = false
        await #expect(throws: Rejected.commit) {
            try await store.readPhotos(draft: seed.pending.draft, validateBeforeRead: {
                if !failAfterRead { throw Rejected.commit }
            }, validateBeforeReturn: {
                reachedFinal = true; throw Rejected.commit
            })
        }
        #expect(reachedFinal == failAfterRead)
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test func cancellationDuringFinalValidationWithholdsPrivateBytes() async throws {
        let seed = try ObservationReanalysisRecoveryTests().seed()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        try await ObservationReanalysisRecoveryTests().publish(seed)
        let store = ObservationReanalysisFileStore(documents: seed.root)
        let task = Task {
            try await store.readPhotos(draft: seed.pending.draft, validateBeforeRead: {}, validateBeforeReturn: {
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test func uploadReadRejectsDigestMatchingNonImageAndDoesNotReturnPartialCohort() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let invalid = try draft(), store = ObservationReanalysisFileStore(documents: root)
        let bytes = try ObservationReanalysisProducerTests().image()
        let valid = ObservationEvidenceUpload.Reference(mediaID: UUID(), contentType: "image/png", byteCount: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let draft = try ObservationReanalysisDraft(identity: invalid.identity, evidence: [.image(valid)] + invalid.evidence)
        try await store.persist(draft: draft, photos: [bytes, Data([1, 2, 3])]) {}
        await #expect(throws: (any Error).self) {
            try await store.readPhotos(draft: draft, validateBeforeRead: {}, validateBeforeReturn: {
                Issue.record("Invalid container reached final admission")
            })
        }
    }

    @Test func fullNamespacePurgeErasesOrphansWithoutFollowingLinks() async throws {
        let root = try directory(), outside = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let queue = root.appendingPathComponent("ReanalysisQueue")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: false)
        let retained = outside.appendingPathComponent("retained.jpg")
        try Data([9]).write(to: retained)
        try Data([7]).write(to: root.appendingPathComponent("unrelated.jpg"))
        for index in 0..<300 {
            let child = queue.appendingPathComponent("orphan-\(index)")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
            try Data([1]).write(to: child.appendingPathComponent(".interrupted.preparing"))
        }
        try FileManager.default.createSymbolicLink(at: queue.appendingPathComponent("outside"), withDestinationURL: outside)
        #expect(mkfifo(queue.appendingPathComponent("fifo").path, 0o600) == 0)
        let store = ObservationReanalysisFileStore(documents: root)
        try await store.purgeNamespace()
        try await store.purgeNamespace()
        #expect(!FileManager.default.fileExists(atPath: queue.path))
        #expect(try Data(contentsOf: retained) == Data([9]))
        #expect(try Data(contentsOf: root.appendingPathComponent("unrelated.jpg")) == Data([7]))
        try FileManager.default.createSymbolicLink(at: queue, withDestinationURL: outside)
        try await store.purgeNamespace()
        #expect(try Data(contentsOf: retained) == Data([9]))
    }

    @Test func fullPurgeRequiresExclusiveRootAndCannotRaceAWriter() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ObservationReanalysisFileStore(documents: root), draft = try draft()
        let lock = open(root.path, O_RDONLY | O_DIRECTORY)
        #expect(lock >= 0); defer { close(lock) }
        #expect(flock(lock, LOCK_SH | LOCK_NB) == 0)
        await #expect(throws: ObservationReanalysisFileStore.Failure.busy) { try await store.purgeNamespace() }
        #expect(flock(lock, LOCK_UN) == 0)
        #expect(flock(lock, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: ObservationReanalysisFileStore.Failure.busy) {
            try await store.persist(draft: draft, photos: [Data([1, 2, 3])]) { Issue.record("Writer entered full purge") }
        }
        #expect(flock(lock, LOCK_UN) == 0)
        try await store.purgeNamespace()
    }

    @Test func exactReplayNeverOverwritesAndRollbackPreservesExistingFiles() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = try draft(), store = ObservationReanalysisFileStore(documents: root), bytes = Data([1, 2, 3])
        let file = root.appendingPathComponent(try #require(draft.photoPaths.first))
        let value = try await store.persist(draft: draft, photos: [bytes]) { 7 }
        #expect(value == 7)
        #expect(try Data(contentsOf: file) == bytes)
        let inode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        await #expect(throws: Rejected.commit) {
            try await store.persist(draft: draft, photos: [bytes]) { throw Rejected.commit }
        }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber == inode)
        try Data([4, 5, 6]).write(to: file)
        await #expect(throws: (any Error).self) { try await store.persist(draft: draft, photos: [bytes]) { 8 } }
        #expect(try Data(contentsOf: file) == Data([4, 5, 6]))
    }

    @Test func failedCommitRemovesOnlyNewFilesAndHoldsCrossInstanceLock() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = try draft(), store = ObservationReanalysisFileStore(documents: root)
        let file = root.appendingPathComponent(try #require(draft.photoPaths.first))
        await #expect(throws: Rejected.commit) {
            try await store.persist(draft: draft, photos: [Data([1, 2, 3])]) {
                let descriptor = open(file.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY)
                #expect(descriptor >= 0)
                defer { close(descriptor) }
                #expect(flock(descriptor, LOCK_EX | LOCK_NB) != 0)
                throw Rejected.commit
            }
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let contents = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(contents.isEmpty)
    }

    @Test func deletionAndNamespaceRecreationCannotRedirectRollback() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = try draft(), store = ObservationReanalysisFileStore(documents: root)
        let file = root.appendingPathComponent(try #require(draft.photoPaths.first))
        await #expect(throws: (any Error).self) {
            try await store.persist(draft: draft, photos: [Data([1, 2, 3])]) {
                let directory = file.deletingLastPathComponent()
                try FileManager.default.removeItem(at: directory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                try Data([9]).write(to: file)
                throw Rejected.commit
            }
        }
        #expect(try Data(contentsOf: file) == Data([9]))
    }

    @Test func sameDirectoryReplacementSurvivesRollback() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = try draft(), store = ObservationReanalysisFileStore(documents: root)
        let file = root.appendingPathComponent(try #require(draft.photoPaths.first))
        await #expect(throws: Rejected.commit) {
            try await store.persist(draft: draft, photos: [Data([1, 2, 3])]) {
                let inode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
                try FileManager.default.removeItem(at: file)
                try Data([9]).write(to: file)
                #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber != inode)
                throw Rejected.commit
            }
        }
        #expect(try Data(contentsOf: file) == Data([9]))
    }

    @Test func symlinkAndWrongBuffersFailBeforeCommit() async throws {
        let root = try directory(), outside = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let draft = try draft(), store = ObservationReanalysisFileStore(documents: root)
        let queue = root.appendingPathComponent("ReanalysisQueue")
        try FileManager.default.createSymbolicLink(at: queue, withDestinationURL: outside)
        await #expect(throws: (any Error).self) {
            try await store.persist(draft: draft, photos: [Data([1, 2, 3])]) { Issue.record("Unexpected commit"); return false }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        await #expect(throws: (any Error).self) {
            try await store.persist(draft: draft, photos: [Data([3, 2, 1])]) { Issue.record("Unexpected commit"); return false }
        }
    }

    @Test func specialFileCannotBlockOrMasqueradeAsPhoto() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = try draft(), file = root.appendingPathComponent(try #require(draft.photoPaths.first))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(mkfifo(file.path, 0o600) == 0)
        await #expect(throws: ObservationReanalysisFileStore.Failure.conflict) {
            try await ObservationReanalysisFileStore(documents: root).persist(draft: draft, photos: [Data([1, 2, 3])]) {
                Issue.record("Special file committed")
            }
        }
    }
}
