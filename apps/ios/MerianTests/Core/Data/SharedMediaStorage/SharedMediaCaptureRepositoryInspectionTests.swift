import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture artifact repository inspection", .serialized)
@MainActor
struct SharedMediaCaptureRepositoryInspectionTests {
    @MainActor struct Store {
        let base: SharedMediaNativeAppBootstrapTests.Store
        let container: ModelContainer, startup: NativeReleaseStartupAdmission
        let profile: SharedMediaNativeAppProfile
        let request: SharedMediaCaptureArtifactRequest
        let bytes = Data(repeating: 7, count: 48)
        var root: URL { base.parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName) }
        var namespace: URL { root.appendingPathComponent(SharedMediaCaptureRootJournal.childName) }
        var final: URL { namespace.appendingPathComponent(request.finalName) }

        init() async throws {
            let base = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true)
            self.base = base
            let initial = try base.owner()
            _ = try await base.open(initial)
            #expect(await initial.invalidateAndAwaitForAccountTransition())
            (container, startup) = try base.startup()
            let discovery = try SharedMediaNativeBootstrapDiscovery.qualification(container: container,
                startup: startup, parent: base.parent, ownerID: base.ownerID)
            profile = try #require(discovery.existingProfile)
            let owner = try base.dispatchOwner()
            _ = try await owner.openApp(container: container, discovery: discovery)
            _ = try await owner.recoverAppCaptureRoot()
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            // Install an exact synthetic ready artifact while no native owner
            // holds the store. This fixture is not a production writer.
            let root = base.parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName)
            let count = getxattr(root.path, SharedMediaCaptureRootJournal.marker, nil, 0, 0, 0)
            guard count > 0, count <= 4096 else { throw SharedMediaStorageFailure.conflict }
            var marker = Data(count: count)
            guard marker.withUnsafeMutableBytes({ getxattr(root.path, SharedMediaCaptureRootJournal.marker,
                $0.baseAddress, count, 0, 0) }) == count else { throw SharedMediaStorageFailure.conflict }
            let context = ModelContext(container); context.autosaveEnabled = false
            let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            request = try .init(id: UUID(), profile: profile, writerEpoch: UUID(), scanID: UUID(), submissionGeneration: UUID(),
                planSHA256: String(repeating: "c", count: 64), rootBindingSHA256: SharedMediaAcquisitionEncoding.digest(marker),
                inventoryRevision: inventory.revision, mediaID: UUID(), itemIndex: 0, role: .sourceAudio, frameIndex: nil,
                contentType: "audio/wav", byteCount: 48, sha256: SharedMediaAcquisitionEncoding.digest(bytes),
                allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
            let namespace = root.appendingPathComponent(SharedMediaCaptureRootJournal.childName)
            let partial = namespace.appendingPathComponent(request.partialName), final = namespace.appendingPathComponent(request.finalName)
            try Data().write(to: partial)
            let partialIdentity = try Self.identity(partial)
            try bytes.write(to: partial)
            try FileManager.default.moveItem(at: partial, to: final)
            let finalIdentity = try Self.identity(final)
            inventory.revision += 3
            let stage = try SharedMediaCaptureArtifactStage(request: request, inventoryRevision: inventory.revision,
                partialIdentity: partialIdentity, finalIdentity: finalIdentity)
            let row = SharedMediaOrdinaryArtifactRecord(id: request.id, inventoryID: profile.inventoryID,
                inventoryGeneration: profile.generation, ownerID: profile.ownerID, recipientScanID: request.scanID,
                submissionGeneration: request.submissionGeneration, mediaID: request.mediaID, itemIndex: 0,
                roleRaw: request.role.rawValue, frameIndex: nil, allocationID: request.allocationID,
                referenceID: request.referenceID, leaseID: request.leaseID, writerEpoch: request.writerEpoch,
                requestData: try request.encoded(), requestSHA256: try request.digest)
            row.phaseRaw = "ready"; row.revision = 2
            row.stageReceiptData = try stage.encoded(request: request)
            row.stageReceiptSHA256 = SharedMediaAcquisitionEncoding.digest(try stage.encoded(request: request))
            context.insert(row)
            context.insert(SharedMediaAllocationRecord(id: request.allocationID, inventoryID: profile.inventoryID,
                accountID: profile.ownerID, packageID: request.scanID, namespaceRaw: SharedMediaCaptureRootJournal.namespace,
                fileToken: request.finalName, poolRaw: "durable", stateRaw: "ready", materializedBytes: 48,
                reservedBytes: 0, physicalIdentity: finalIdentity))
            context.insert(SharedMediaLeaseRecord(id: request.leaseID, allocationID: request.allocationID,
                processEpoch: request.writerEpoch, purposeRaw: SharedMediaCaptureArtifactLedger.leasePurpose, stateRaw: "closed"))
            context.insert(SharedMediaReferenceRecord(id: request.referenceID, allocationID: request.allocationID,
                accountID: profile.ownerID, ownerID: request.id.uuidString.lowercased(),
                roleRaw: SharedMediaCaptureRootJournal.namespace, stateRaw: "held", revision: 0))
            try context.save()
        }

        func open(pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeOriginalOwner {
            let discovery = try SharedMediaNativeBootstrapDiscovery.qualification(container: container,
                startup: startup, parent: base.parent, ownerID: base.ownerID)
            let owner = try base.dispatchOwner()
            try owner.configureAppOpeningForTesting(pause: pause)
            let result = try await owner.openApp(container: container, discovery: discovery)
            guard case .captureRootRecovery = result else { throw SharedMediaStorageFailure.conflict }
            return owner
        }
        static func identity(_ url: URL) throws -> String {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw SharedMediaStorageFailure.unavailable }
            return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        }
    }

    @Test func repeatedInspectionAndColdReopenUseFreshLocksWithoutEnablingMutations() async throws {
        let store = try await Store(), controls = try store.base.controls()
        let owner = try await store.open()
        let first = try await owner.inspectAppCaptureArtifacts()
        #expect(first.allocations == 1 && first.pendingPackages == 0)
        #expect(try await owner.inspectAppCaptureArtifacts() == first)
        #expect(!owner.isReadyForAppDispatch)
        await #expect(throws: (any Error).self) { _ = try await owner.inspectApp() }
        await #expect(throws: (any Error).self) { _ = try await owner.appMetadataWorkflow { _ in true } }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        #expect(try await cold.inspectAppCaptureArtifacts() == first)
        #expect(try store.base.controls() == controls)
        #expect(try Data(contentsOf: store.final) == store.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaCaptureRootBoundary.allCases)
    func interruptedRootSetupReleasesLocksAndRetainsOnlyRecordedOwnership(_ boundary: SharedMediaCaptureRootBoundary) async throws {
        let base = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true), initial = try base.owner()
        _ = try await base.open(initial)
        #expect(await initial.invalidateAndAwaitForAccountTransition())
        let (container, startup) = try base.startup()
        let discovery = try SharedMediaNativeBootstrapDiscovery.qualification(container: container,
            startup: startup, parent: base.parent, ownerID: base.ownerID)
        let owner = try base.dispatchOwner()
        _ = try await owner.openApp(container: container, discovery: discovery)
        try owner.configureCaptureRootRecoveryForTesting { if $0 == boundary { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { _ = try await owner.inspectAppCaptureArtifacts() }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try SharedMediaNativeBootstrapDiscovery.qualification(container: container,
            startup: startup, parent: base.parent, ownerID: base.ownerID)
        let next = try base.dispatchOwner()
        _ = try await next.openApp(container: container, discovery: cold)
        if boundary == .afterRootDirectory || boundary == .afterNamespaceDirectory {
            await #expect(throws: (any Error).self) { _ = try await next.inspectAppCaptureArtifacts() }
        } else { #expect(try await next.inspectAppCaptureArtifacts().allocations == 0) }
        #expect(!next.isReadyForAppDispatch)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["missing", "changed", "orphan"])
    func invalidPhysicalEvidenceRemainsHeldAndNeverQualifiesDispatch(_ mutation: String) async throws {
        let store = try await Store(), owner = try await store.open()
        switch mutation {
        case "missing": try FileManager.default.removeItem(at: store.final)
        case "changed": try Data(repeating: 8, count: 48).write(to: store.final)
        case "orphan": try Data([1]).write(to: store.namespace.appendingPathComponent(UUID().uuidString.lowercased()))
        default: Issue.record("Unknown mutation")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: store.namespace.path)
        await #expect(throws: (any Error).self) { _ = try await owner.inspectAppCaptureArtifacts() }
        #expect(!owner.isReadyForAppDispatch)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.namespace.path) == names)
        let context = ModelContext(store.container); context.autosaveEnabled = false
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>()) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountDrainWaitsForInspectionAndPreservesArtifacts() async throws {
        let store = try await Store(), gate = Gate(), owner = try await store.open(pause: { await gate.pause() })
        let inspection = Task { @MainActor in
            do { let value = try await owner.inspectAppCaptureArtifacts(); await gate.finish(); return value } catch {
                await gate.finish(); throw error
            }
        }
        guard await gate.entered() else { _ = try await inspection.value; Issue.record("No suspension"); return }
        var drained = false
        let drain = Task { @MainActor in let value = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return value }
        await Task.yield()
        #expect(!drained)
        await gate.release()
        await #expect(throws: (any Error).self) { _ = try await inspection.value }
        #expect(await drain.value)
        #expect(try Data(contentsOf: store.final) == store.bytes)
        let next = try await store.open()
        #expect(try await next.inspectAppCaptureArtifacts().allocations == 1)
        #expect(await next.invalidateAndAwaitForAccountTransition())
    }

    private actor Gate {
        var arrived = false, finished = false, released = false
        var arrival: CheckedContinuation<Bool, Never>?, waiting: CheckedContinuation<Void, Never>?
        func pause() async {
            guard !released else { return }
            arrived = true; arrival?.resume(returning: true); arrival = nil
            await withCheckedContinuation { waiting = $0 }
        }
        func entered() async -> Bool {
            if arrived { return true }; if finished { return false }
            return await withCheckedContinuation { arrival = $0 }
        }
        func finish() { finished = true; arrival?.resume(returning: arrived); arrival = nil }
        func release() { released = true; waiting?.resume(); waiting = nil }
    }
}
