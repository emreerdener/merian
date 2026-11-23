import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture artifact physical inventory", .serialized)
@MainActor
struct SharedMediaCaptureArtifactFilesTests {
    @MainActor final class Store {
        let parent: URL, files: SharedMediaCaptureArtifactFiles
        let ledger: SharedMediaCaptureArtifactLedgerTests.Store
        let submission: SharedMediaCaptureSubmission?
        let bytes = Data(repeating: 7, count: 48)
        var request: SharedMediaCaptureArtifactRequest { ledger.request }
        var namespace: URL { parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName)
            .appendingPathComponent(SharedMediaCaptureRootJournal.childName) }
        var partial: URL { namespace.appendingPathComponent(request.partialName) }
        var final: URL { namespace.appendingPathComponent(request.finalName) }

        init(fullSchema: Bool = false, capturePlan: Bool = false) throws {
            parent = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
                .appendingPathComponent("capture-inventory-test-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let profile = SharedMediaNativeAppProfile(ownerID: UUID(), inventoryID: UUID(), generation: UUID(),
                storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "a", count: 64),
                receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: .physicalRootsV1)
            let controls = try SharedMediaNativeCaptureRootFiles.qualification(parent: parent, profile: profile, createOrResume: true)
            files = try .init(controls: controls, rootURL: parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName, isDirectory: true))
            let id = UUID(), scan = UUID(), generation = UUID(), media = UUID()
            let plan = try CaptureInitialEvidencePlan(ownerID: profile.ownerID, scanID: scan, generation: generation,
                items: [.audio(.init(source: .init(mediaID: media, contentType: "audio/wav", byteCount: 48,
                    sha256: SharedMediaAcquisitionEncoding.digest(bytes)), preparedMediaID: UUID()))])
            submission = capturePlan ? try .init(plan: plan, context: SharedMediaCaptureSubmissionContextTests.context(plan), profile: profile, writerEpoch: UUID(), inventoryRevision: 3,
                rootBindingSHA256: files.rootBindingSHA256, eventID: UUID(), artifactIDs: [id]) : nil
            let request = try SharedMediaCaptureArtifactRequest(id: id, profile: profile, writerEpoch: UUID(),
                scanID: scan, submissionGeneration: generation, planSHA256: submission?.observation.sha256 ?? String(repeating: "c", count: 64),
                rootBindingSHA256: files.rootBindingSHA256, inventoryRevision: 4, mediaID: media, itemIndex: 0,
                role: .sourceAudio, frameIndex: nil, contentType: "audio/wav", byteCount: 48,
                sha256: SharedMediaAcquisitionEncoding.digest(bytes), allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
            ledger = try .init(request: request, fullSchema: fullSchema || capturePlan)
            if let submission {
                let data = try submission.encoded()
                ledger.context.insert(SharedMediaOrdinarySubmissionRecord(inventoryID: profile.inventoryID,
                    inventoryGeneration: profile.generation, ownerID: profile.ownerID, recipientScanID: scan,
                    submissionGeneration: generation, jobID: submission.jobID, eventID: submission.eventID,
                    writerEpoch: submission.writerEpoch, formatRaw: submission.format.rawValue, requestData: data,
                    requestSHA256: SharedMediaAcquisitionEncoding.digest(data), observationSHA256: submission.observation.sha256))
                try ledger.context.save()
            }
        }
        deinit { try? FileManager.default.removeItem(at: parent) }

        func audit(checkpoint: () throws -> Void = {}) async throws -> SharedMediaCaptureArtifactFiles.Inventory {
            try await files.verify(context: ledger.context, profile: request.profile, checkpoint: checkpoint)
        }
        func identity(_ url: URL) throws -> String {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw SharedMediaStorageFailure.unavailable }
            return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        }
        func begin() throws -> String {
            try Data().write(to: partial)
            let saved = try identity(partial)
            try save(partial: saved, final: nil)
            return saved
        }
        func save(partial: String, final: String?) throws {
            let ready = final != nil
            ledger.inventory.revision = ready ? 7 : 6
            let stage = try SharedMediaCaptureArtifactStage(request: request, inventoryRevision: ledger.inventory.revision,
                partialIdentity: partial, finalIdentity: final)
            ledger.row.phaseRaw = ready ? "ready" : "writing"; ledger.row.revision = ready ? 2 : 1
            ledger.row.stageReceiptData = try stage.encoded(request: request)
            ledger.row.stageReceiptSHA256 = SharedMediaAcquisitionEncoding.digest(try stage.encoded(request: request))
            ledger.allocation.stateRaw = ledger.row.phaseRaw
            ledger.allocation.physicalIdentity = final ?? partial
            ledger.allocation.materializedBytes = ready ? 48 : 0; ledger.allocation.reservedBytes = ready ? 0 : 48
            ledger.lease.stateRaw = ready ? "closed" : "open"
            try ledger.context.save()
        }
        func finish(ready: Bool = true) throws -> String {
            let saved = try begin()
            try bytes.write(to: partial)
            try FileManager.default.moveItem(at: partial, to: final)
            if ready { try save(partial: saved, final: identity(final)) }
            return saved
        }
    }

    @Test func reservationsAndInterruptedEmptyCreationStayDistinct() async throws {
        let store = try Store()
        let empty = try await store.audit()
        #expect(empty.physicalBytes == 0 && empty.ambiguousEmptyPartials == 0 && empty.ledger.reservedBytes == 48)
        try Data().write(to: store.partial)
        let ambiguous = try await store.audit()
        #expect(ambiguous.physicalBytes == 0 && ambiguous.ambiguousEmptyPartials == 1)
        #expect(store.ledger.row.phaseRaw == "reserved" && store.ledger.row.stageReceiptData == nil)
        #expect(try await store.audit() == ambiguous)
        try Data([1]).write(to: store.partial)
        await #expect(throws: (any Error).self) { _ = try await store.audit() }
    }

    @Test func writingAndRenameInterruptionRetainTheirOriginalInode() async throws {
        let store = try Store(), saved = try store.begin()
        try Data([7, 7]).write(to: store.partial)
        #expect(try await store.audit().physicalBytes == 2)
        try store.bytes.write(to: store.partial)
        try FileManager.default.moveItem(at: store.partial, to: store.final)
        let interrupted = try await store.audit()
        #expect(interrupted.physicalBytes == 48 && interrupted.ledger.reservedBytes == 48)
        #expect(store.ledger.row.phaseRaw == "writing")
        try store.save(partial: saved, final: store.identity(store.final))
        let ready = try await store.audit()
        #expect(ready.physicalBytes == 48 && ready.ledger.materializedBytes == 48 && ready.ledger.reservedBytes == 0)
        #expect(try await store.audit() == ready)
        #expect(throws: (any Error).self) { try SharedMediaStorageLookup.requireNoUnqualifiedCaptureArtifacts(store.ledger.context) }
    }

    @Test(arguments: ["missing", "orphan", "both", "symlink", "hardlink", "directory", "replacement", "hash"])
    func rejectsPhysicalDriftWithoutAdoptingOrDeletingIt(_ mutation: String) async throws {
        let store = try Store(), saved = try store.finish()
        switch mutation {
        case "missing": try FileManager.default.removeItem(at: store.final)
        case "orphan": try Data([1]).write(to: store.namespace.appendingPathComponent(UUID().uuidString.lowercased()))
        case "both": try Data().write(to: store.partial)
        case "symlink", "directory", "replacement":
            try FileManager.default.moveItem(at: store.final, to: store.parent.appendingPathComponent("saved"))
            if mutation == "symlink" {
                try FileManager.default.createSymbolicLink(at: store.final, withDestinationURL: store.parent.appendingPathComponent("saved"))
            } else if mutation == "directory" {
                try FileManager.default.createDirectory(at: store.final, withIntermediateDirectories: false)
            } else { try store.bytes.write(to: store.final) }
        case "hardlink": try FileManager.default.linkItem(at: store.final, to: store.parent.appendingPathComponent("linked"))
        case "hash":
            try Data(repeating: 8, count: 48).write(to: store.final)
            // Even a coherently restated descriptor cannot hide wrong bytes.
            try store.save(partial: saved, final: store.identity(store.final))
        default: Issue.record("Unknown mutation")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: store.namespace.path)
        await #expect(throws: (any Error).self) { _ = try await store.audit() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.namespace.path) == names)
    }

    @Test func rootReplacementAndAccountFenceExpireInspection() async throws {
        let store = try Store()
        await #expect(throws: SharedMediaStorageFailure.stale) {
            _ = try await store.audit { throw SharedMediaStorageFailure.stale }
        }
        let root = store.parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName)
        try FileManager.default.moveItem(at: root, to: store.parent.appendingPathComponent("moved"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { _ = try await store.audit() }
    }

    @Test(arguments: ["missing", "orphan", "bytes", "revision"])
    func physicalAndStoreChangesAfterHashingInvalidateTheResult(_ mutation: String) async throws {
        let store = try Store()
        _ = try store.finish()
        defer { store.files.afterByteAudit = nil }
        store.files.afterByteAudit = {
            switch mutation {
            case "missing": try FileManager.default.removeItem(at: store.final)
            case "orphan": try Data([1]).write(to: store.namespace.appendingPathComponent(UUID().uuidString.lowercased()))
            case "bytes": try Data(repeating: 8, count: 48).write(to: store.final)
            case "revision": store.ledger.inventory.revision += 1; try store.ledger.context.save()
            default: Issue.record("Unknown mutation")
            }
        }
        await #expect(throws: (any Error).self) { _ = try await store.audit() }
    }

    @Test func cancellationAfterHashingCannotReturnAnInventory() async throws {
        let store = try Store()
        _ = try store.finish()
        defer { store.files.afterByteAudit = nil }
        store.files.afterByteAudit = { withUnsafeCurrentTask { $0?.cancel() } }
        let operation = Task { @MainActor in try await store.audit() }
        await #expect(throws: CancellationError.self) { _ = try await operation.value }
        #expect(store.ledger.row.phaseRaw == "ready")
        #expect(try Data(contentsOf: store.final) == store.bytes)
    }
}
