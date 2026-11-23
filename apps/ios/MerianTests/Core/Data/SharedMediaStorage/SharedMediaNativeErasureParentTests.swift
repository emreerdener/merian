import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct NativeErasureParentTests {
    private enum Interruption: Error { case injected }
    private struct SetupFailure: Error { let stage: String; let underlying: any Error }

    @Test(arguments: ["absent", "empty", "retired"])
    func completionAuditsEveryNativeTableOnceAndRejectsNewRows(parent state: String) async throws {
        let fixture = try Fixture(deletion: true, createParent: state != "absent")
        if state == "retired" { _ = try await fixture.prepareSources(capture: .afterMarker) }
        let completion = try await SharedMediaNativeLibraryErasure.qualification(container: fixture.container,
            admission: fixture.admission, authorization: .accountDeletion(fixture.deletionScope()),
            support: fixture.parent.deletingLastPathComponent(), runtimeCheckpoint: {})
        let passes = try SharedMediaNativeErasureGraph.countSnapshotsForTesting(container: fixture.container) {
            try completion.validate(in: fixture.container)
        }
        #expect(passes == 1)
        let context = ModelContext(fixture.container)
        context.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: UUID(), processEpoch: UUID(),
            purposeRaw: "captureArtifactV1", stateRaw: "closed"))
        try context.save()
        #expect(throws: (any Error).self) { try completion.validate(in: fixture.container) }
    }

    @Test func accountDeletionAdapterJoinsExitAndRetriesHistoryAfterNativeTerminal() async throws {
        let fixture = try Fixture(deletion: true)
        _ = try await fixture.prepareSources(capture: .afterMarker)
        let paths = try await fixture.captureOriginals()
        let suite = "merian.tests.native-erasure." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        FieldNotesStore.setFieldNotes("Synthetic retained note", for: "fixture", userDefaults: defaults)
        let documents = try fixture.historyDocuments()
        let context = ModelContext(fixture.container)
        context.insert(OfflineJobRecord(id: "synthetic-erasure", kind: .observationReanalysisSync)); try context.save()
        let scope = try fixture.deletionScope()
        let operation = scope.cleanupOperationID
        var attempts = 0, runtimeResets = 0, derivedResets = 0
        let first = try fixture.coordinator(documents: documents, defaults: defaults, beforeHistory: {
            attempts += 1
            try SharedMediaNativeErasureJournal.requireNoNativeRows(container: fixture.container, checkpoint: {})
            #expect(!FileManager.default.fileExists(atPath: paths.final.path))
            #expect(!FileManager.default.fileExists(atPath: paths.partial.path))
            #expect(FieldNotesStore.hasStoredValues(userDefaults: defaults))
            throw Interruption.injected
        }, resetRuntime: { runtimeResets += 1 })
        let gate = InferenceOperationGate(), consumer = NSObject()
        let work = Task { await gate.wait() }
        await gate.waitUntilStarted()
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: fixture.ownerID, runtime: AuthRuntimeState())
        _ = try first.nativeMediaLifecycle.preparedInputBorrowForTesting(container: fixture.container,
            account: account, consumer: consumer, install: { _ in }, close: {
                work.cancel(); await work.value; return true
            })
        let lifetime = try #require(first.nativeMediaLifecycle.nativeMediaLifetime)
        let closing = Task { await lifetime.shutdown() }
        while !lifetime.isClosed { await Task.yield() }
        #expect(!lifetime.shutdownFinished)
        #expect(await first.nativeMediaLifecycle.libraryCleanup.purgeLibraryForAccountDeletion(modelContext: context, scope: scope,
            resetDerivedState: { derivedResets += 1 }) == false)
        #expect(attempts == 0 && FileManager.default.fileExists(atPath: paths.final.path))
        await gate.release(); #expect(await closing.value)
        #expect(await first.nativeMediaLifecycle.libraryCleanup.purgeLibraryForAccountDeletion(modelContext: context, scope: scope,
            resetDerivedState: { derivedResets += 1 }) == false)
        #expect(attempts == 1 && runtimeResets == 0 && derivedResets == 0)
        #expect(scope.isCurrent && scope.cleanupOperationID == operation)
        #expect(FieldNotesStore.hasStoredValues(userDefaults: defaults))
        for name in ["ReanalysisQueue", "ReanalysisInputs"] {
            #expect(FileManager.default.fileExists(atPath: documents.appendingPathComponent(name).path))
        }
        // A fresh coordinator has no current Auth session or enrollment. It
        // recovers under the same accepted operation and retained terminal.
        let retry = try fixture.coordinator(documents: documents, defaults: defaults, beforeHistory: {
            attempts += 1
            #expect(scope.cleanupOperationID == operation && scope.isCurrent)
        }, resetRuntime: { runtimeResets += 1 })
        #expect(retry.supabaseManager.currentUser == nil)
        #expect(await retry.nativeMediaLifecycle.libraryCleanup.purgeLibraryForAccountDeletion(modelContext: ModelContext(fixture.container),
            scope: scope, resetDerivedState: { derivedResets += 1 }))
        #expect(attempts == 2 && runtimeResets == 1 && derivedResets == 1)
        #expect(!FieldNotesStore.hasStoredValues(userDefaults: defaults))
        for name in ["ReanalysisQueue", "ReanalysisInputs"] {
            #expect(!FileManager.default.fileExists(atPath: documents.appendingPathComponent(name).path))
        }
        #expect(retry.nativeMediaLifecycle.libraryCleanup.acknowledgeDeletionPurge(for: retry.supabaseManager, scope: scope))
    }

    @Test(arguments: [false, true])
    func accountDeletionCompletionRejectsParentChangeAcrossHistoryAwait(existing: Bool) async throws {
        let fixture = try Fixture(deletion: true, createParent: existing)
        let suite = "merian.tests.native-erasure-parent." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        FieldNotesStore.setFieldNotes("Synthetic retained note", for: "fixture", userDefaults: defaults)
        let documents = try fixture.historyDocuments(), scope = try fixture.deletionScope()
        let gate = InferenceOperationGate()
        var resets = 0
        let di = try fixture.coordinator(documents: documents, defaults: defaults,
            beforeHistory: { await gate.wait() }, resetRuntime: { resets += 1 })
        let task = Task { await di.nativeMediaLifecycle.libraryCleanup.purgeLibraryForAccountDeletion(
            modelContext: ModelContext(fixture.container), scope: scope, resetDerivedState: { resets += 1 }) }
        await gate.waitUntilStarted()
        if existing {
            try FileManager.default.moveItem(at: fixture.parent,
                to: fixture.parent.deletingLastPathComponent().appendingPathComponent("preserved-parent"))
        }
        try FileManager.default.createDirectory(at: fixture.parent, withIntermediateDirectories: false)
        await gate.release()
        #expect(await task.value == false)
        #expect(resets == 0 && scope.isCurrent)
        #expect(FieldNotesStore.hasStoredValues(userDefaults: defaults))
    }

    @Test(arguments: ["unchanged", "replacement", "nonempty", "symlink"])
    func captureReadyAndUnreceiptedEmptyPartialUseFrozenErasureClosure(change: String) async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources(capture: .afterMarker)
        let paths = try await fixture.captureOriginals()
        #expect(try Data(contentsOf: paths.partial).isEmpty)
        try await fixture.requireNormalCaptureInspectionClosed()
        var parent: SharedMediaNativeErasureParent? = try fixture.open()
        var saves = 0
        await #expect(throws: Interruption.self) {
            _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container, parent: parent!,
                operationID: fixture.operationID, journalBoundary: { boundary in
                    if boundary == .beforeSave { saves += 1; if saves == 2 { throw Interruption.injected } }
                })
        }
        parent = nil
        #expect(FileManager.default.fileExists(atPath: paths.final.path))
        if change == "replacement" || change == "symlink" {
            let preserved = fixture.parent.deletingLastPathComponent().appendingPathComponent("preserved-partial")
            try FileManager.default.moveItem(at: paths.partial, to: preserved)
            if change == "replacement" { try Data().write(to: paths.partial) } else { try FileManager.default.createSymbolicLink(at: paths.partial, withDestinationURL: preserved) }
        } else if change == "nonempty" { try Data([1]).write(to: paths.partial) }
        let reopened = try fixture.open()
        if change == "unchanged" {
            let completion = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
                parent: reopened, operationID: fixture.operationID)
            try completion.validate(in: fixture.container)
            #expect(!FileManager.default.fileExists(atPath: paths.final.path))
            #expect(!FileManager.default.fileExists(atPath: paths.partial.path))
        } else {
            await #expect(throws: (any Error).self) {
                _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
                    parent: reopened, operationID: fixture.operationID)
            }
            #expect(FileManager.default.fileExists(atPath: paths.final.path))
            #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>()) == 2)
        }
    }

    @Test(arguments: ["parent", "row", "scope", "runtime"])
    func absentParentProbeRetainsFenceAndRejectsNewLiability(change: String) throws {
        let fixture = try Fixture(createParent: false)
        let probe = try #require(try fixture.emptyProbe())
        try probe.requireCurrent()
        #expect(throws: (any Error).self) { _ = try fixture.admission.acquireFence(container: fixture.container) }
        if change == "parent" {
            try FileManager.default.createDirectory(at: fixture.parent, withIntermediateDirectories: false)
        } else if change == "row" {
            let context = ModelContext(fixture.container); context.autosaveEnabled = false
            context.insert(PhotoPreparationAsset(id: UUID(), ownerID: fixture.ownerID, generation: UUID(),
                fileToken: "synthetic", contentType: "public.png", byteCount: 1, sha256: String(repeating: "a", count: 64), acquisitionKindRaw: "camera", cleanupStateRaw: "live"))
            try context.save()
        } else if change == "scope" { fixture.scopeCurrent = false } else { fixture.runtimeCurrent = false }
        #expect(throws: (any Error).self) { try probe.requireCurrent() }
    }

    @Test(arguments: [false, true])
    func completeLibraryErasureRetainsTerminalAndColdRecovery(capture: Bool) async throws {
        let fixture = try Fixture(deletion: capture)
        _ = try await fixture.prepareSources(capture: capture ? .afterMarker : nil)
        var parent: SharedMediaNativeErasureParent? = try fixture.open()
        var completion: SharedMediaNativeLibraryErasure.Completion? = try await SharedMediaNativeLibraryErasure.erase(
            container: fixture.container, parent: parent!, operationID: fixture.operationID)
        try completion!.validate(in: fixture.container)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.parent.path) == [SharedMediaNativeBootstrapCodec.parentReceiptName])
        completion = nil; parent = nil
        let reopened = try fixture.open()
        let recovered = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
            parent: reopened, operationID: fixture.operationID)
        try recovered.validate(in: fixture.container)
        fixture.scopeCurrent = false
        #expect(throws: (any Error).self) { try recovered.validate(in: fixture.container) }
    }

    @Test(arguments: ["staged", "received", "replacement", "unreserved"])
    func populatedPhotoReceivingAndInterruptedOriginalRetireTogether(state: String) async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources()
        let paths = try await fixture.photoOriginals(received: state != "staged", reserve: state != "unreserved")
        let assetCount = try ModelContext(fixture.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>())
        var parent: SharedMediaNativeErasureParent? = try fixture.open()
        if state == "unreserved" {
            await #expect(throws: (any Error).self) {
                _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
                    parent: parent!, operationID: fixture.operationID)
            }
            #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 0)
            #expect(FileManager.default.fileExists(atPath: paths.final.path))
            #expect(FileManager.default.fileExists(atPath: paths.partial.path))
            return
        }
        var saves = 0
        await #expect(throws: Interruption.self) {
            _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container, parent: parent!,
                operationID: fixture.operationID, journalBoundary: { boundary in
                    if boundary == .beforeSave { saves += 1; if saves == 2 { throw Interruption.injected } }
                })
        }
        parent = nil
        if state == "replacement" {
            try FileManager.default.moveItem(at: paths.partial,
                to: fixture.parent.deletingLastPathComponent().appendingPathComponent("preserved-original"))
            try Data([1, 2]).write(to: paths.partial)
        }
        let reopened = try fixture.open()
        if state == "replacement" {
            await #expect(throws: (any Error).self) {
                _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
                    parent: reopened, operationID: fixture.operationID)
            }
            #expect(FileManager.default.fileExists(atPath: paths.final.path))
            #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == assetCount)
        } else {
            let completion = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
                parent: reopened, operationID: fixture.operationID)
            try completion.validate(in: fixture.container)
            #expect(!FileManager.default.fileExists(atPath: paths.partial.path))
            #expect(!FileManager.default.fileExists(atPath: paths.final.path))
        }
    }

    @Test(arguments: ["absent", "previousOperation", "malformed", "storeMismatch"])
    func emptyParentRequiresIndependentCurrentOperationAndOptionalValidReceipt(state: String) async throws {
        let fixture = try Fixture(), parent = try fixture.open()
        if state != "absent" {
            let receipt = try fixture.terminal(parent)
            var object = try #require(JSONSerialization.jsonObject(with: receipt.encoded()) as? [String: Any])
            var header = try #require(object["header"] as? [String: Any])
            header[state == "storeMismatch" ? "storeFileIdentity" : "operationID"] = state == "storeMismatch" ? "1:2" : UUID().uuidString
            object["header"] = header
            let changed = try JSONDecoder().decode(SharedMediaNativeErasureTerminalReceipt.self,
                from: JSONSerialization.data(withJSONObject: object))
            try fixture.write(changed)
            if state == "malformed" {
                #expect(setxattr(fixture.parent.path, SharedMediaNativeErasureTerminalReceipt.marker, nil, 0, 0, 0) == 0)
            }
        }
        if state == "malformed" || state == "storeMismatch" {
            await #expect(throws: (any Error).self) {
                _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container, parent: parent,
                    operationID: fixture.operationID)
            }
        } else {
            let completion = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
                parent: parent, operationID: fixture.operationID)
            try completion.validate(in: fixture.container)
            fixture.scopeCurrent = false
            #expect(throws: (any Error).self) { try completion.validate(in: fixture.container) }
        }
    }

    @Test(arguments: ["preparing", "beforeUnlink", "afterUnlink"])
    func completeLibraryErasureResumesExactInterruptedOperation(at point: String) async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources(capture: .afterMarker)
        var parent: SharedMediaNativeErasureParent? = try fixture.open()
        var saves = 0, interrupted = false
        await #expect(throws: Interruption.self) {
            _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container, parent: parent!,
                operationID: fixture.operationID, journalBoundary: { boundary in
                    if boundary == .beforeSave { saves += 1 }
                    if point == "preparing", saves == 2, boundary == .beforeSave { throw Interruption.injected }
                }, treeBoundary: { boundary in
                    if !interrupted, (point == "beforeUnlink" && boundary == .beforeUnlink)
                        || (point == "afterUnlink" && boundary == .afterUnlink) {
                        interrupted = true; throw Interruption.injected
                    }
                })
        }
        parent = nil
        let reopened = try fixture.open()
        let completion = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container,
            parent: reopened, operationID: fixture.operationID)
        try completion.validate(in: fixture.container)
    }

    @Test func manifestBuilderRejectsUnownedPhotoAndInboxLeavesBeforeIntent() async throws {
        for inbox in [false, true] {
            let fixture = try Fixture(), profile = try await fixture.prepareSources()
            let url = inbox ? fixture.parent.appendingPathComponent("inbox/InboxSources/" + UUID().uuidString.lowercased())
                : fixture.parent.appendingPathComponent("photo/PhotoPreparation/" + profile.ownerID.uuidString.lowercased())
                    .appendingPathComponent(UUID().uuidString.lowercased()).appendingPathComponent(UUID().uuidString.lowercased())
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
            let parent = try fixture.open()
            await #expect(throws: (any Error).self) {
                _ = try await SharedMediaNativeLibraryErasure.erase(container: fixture.container, parent: parent, operationID: fixture.operationID)
            }
            #expect(try Data(contentsOf: url) == Data([1]))
            #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 0)
        }
    }

    @Test func initialSourcesPreserveControlsAndHoldEveryRoot() async throws {
        let fixture = try Fixture(), profile = try await fixture.prepareSources()
        let parent = try fixture.open(), sources = try parent.openSources()
        #expect(sources.profile == profile && !sources.hasCompleteCapture)
        try sources.check()
        let valid = try fixture.terminal(parent, profile: profile, controlSHA256: sources.controlSHA256).header
        try sources.require(header: valid)
        let foreign = try fixture.terminal(parent, profile: profile).header
        #expect(throws: (any Error).self) { try sources.require(header: foreign) }
        for name in SharedMediaNativeBootstrapCodec.names {
            let fd = open(fixture.parent.appendingPathComponent(name).path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            #expect(fd >= 0)
            #expect(flock(fd, LOCK_EX | LOCK_NB) != 0)
            close(fd)
        }
        let spool = try SharedMediaNativeErasureManifestSpool(ownerID: profile.ownerID, checkpoint: { try sources.check() })
        try sources.appendFixedEntries(to: spool); try await spool.seal()
        let chain = try await spool.visitPages(profile: profile, operationID: UUID()) { _ in }
        #expect(chain.entryCount == 18)
        fixture.runtimeCurrent = false
        #expect(throws: (any Error).self) { try sources.check() }
    }

    @Test(arguments: SharedMediaCaptureRootBoundary.allCases)
    func initialSourcesValidateCapturePrefixesWithoutRepair(boundary: SharedMediaCaptureRootBoundary) async throws {
        let fixture = try Fixture(), profile = try await fixture.prepareSources(capture: boundary)
        let before = try FileManager.default.contentsOfDirectory(atPath: fixture.parent.path).sorted()
        let parent = try fixture.open()
        if boundary == .afterRootDirectory || boundary == .afterNamespaceDirectory {
            #expect(throws: (any Error).self) { _ = try parent.openSources() }
        } else {
            let sources = try parent.openSources()
            #expect(sources.profile == profile)
            #expect(sources.hasCompleteCapture == (boundary == .afterMarker))
            try sources.check()
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.parent.path).sorted() == before)
    }

    @Test(arguments: ["marker", "progress", "namespace", "unexpectedAuthorityFile", "backup"])
    func initialSourcesRejectChangedEvidenceAndReleaseFailedOpenLocks(change: String) async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources()
        let parent = try fixture.open()
        switch change {
        case "marker": #expect(removexattr(fixture.parent.appendingPathComponent("photo").path, "com.merian.p1-shared-v1", 0) == 0)
        case "progress": try Data([1]).write(to: fixture.parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.progressNames[1]))
        case "namespace":
            let url = fixture.parent.appendingPathComponent("photo/PhotoPreparation")
            try FileManager.default.moveItem(at: url, to: fixture.parent.deletingLastPathComponent().appendingPathComponent("preserved"))
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        case "backup":
            var url = fixture.parent.appendingPathComponent("photo"), values = URLResourceValues()
            values.isExcludedFromBackup = false; try url.setResourceValues(values)
        default: try Data([1]).write(to: fixture.parent.appendingPathComponent("authority/foreign"))
        }
        #expect(throws: (any Error).self) { _ = try parent.openSources() }
        let fd = open(fixture.parent.appendingPathComponent("authority").path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        #expect(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
        close(fd)
    }

    @Test(arguments: ["root", "child", "marker", "control"])
    func openedCaptureSourcesRejectReplacement(change: String) async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources(capture: .afterMarker)
        let parent = try fixture.open(), sources = try parent.openSources()
        typealias Capture = SharedMediaCaptureRootJournal
        let root = fixture.parent.appendingPathComponent(Capture.rootName)
        switch change {
        case "root", "child":
            let url = change == "root" ? root : root.appendingPathComponent(Capture.childName)
            try FileManager.default.moveItem(at: url, to: fixture.parent.deletingLastPathComponent().appendingPathComponent("preserved-capture"))
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        case "marker": #expect(removexattr(root.path, Capture.marker, 0) == 0)
        default: try Data([1]).write(to: fixture.parent.appendingPathComponent(Capture.finalName))
        }
        #expect(throws: (any Error).self) { try sources.check() }
    }

    @Test func sourcesRetainParentAndReleaseEveryLockOnExit() async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources(capture: .afterMarker)
        var parent: SharedMediaNativeErasureParent? = try fixture.open()
        var sources: SharedMediaNativeErasureSources? = try parent!.openSources()
        parent = nil
        try sources!.check()
        #expect(throws: (any Error).self) { _ = try fixture.admission.acquireFence(container: fixture.container) }
        sources = nil
        let reopened = try fixture.open(); try reopened.check()
        let roots = try reopened.openSources(); try roots.check()
    }

    @Test func photoInventoryIncludesEmptyDirectoriesAndIsRepeatable() async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources()
        let namespace = fixture.parent.appendingPathComponent("photo/PhotoPreparation")
        let owner = namespace.appendingPathComponent(fixture.ownerID.uuidString.lowercased())
        let package = owner.appendingPathComponent(UUID().uuidString.lowercased())
        let empty = owner.appendingPathComponent(UUID().uuidString.lowercased())
        for url in [package, empty] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try Data([1, 2, 3]).write(to: package.appendingPathComponent(UUID().uuidString.lowercased()))
        let parent = try fixture.open(), sources = try parent.openSources()
        var first: [SharedMediaNativeErasureManifest.Entry] = [], second: [SharedMediaNativeErasureManifest.Entry] = []
        try await sources.visitPhotoEntries { first.append($0) }
        try await sources.visitPhotoEntries { second.append($0) }
        #expect(first == second && first.count == 4)
        #expect(first.filter { $0.kind == .directory }.count == 3)
        #expect(first.filter { $0.kind == .file }.count == 1)
    }

    @Test(arguments: ["foreignOwner", "symlink", "hardlink", "nested", "replacement"])
    func photoInventoryRejectsUnownedShapesAndConcurrentReplacement(change: String) async throws {
        let fixture = try Fixture(); _ = try await fixture.prepareSources()
        let namespace = fixture.parent.appendingPathComponent("photo/PhotoPreparation")
        let ownerID = change == "foreignOwner" ? UUID() : fixture.ownerID
        let package = namespace.appendingPathComponent(ownerID.uuidString.lowercased()).appendingPathComponent(UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let file = package.appendingPathComponent(UUID().uuidString.lowercased())
        switch change {
        case "symlink": try FileManager.default.createSymbolicLink(at: file, withDestinationURL: package)
        case "hardlink":
            try Data([1]).write(to: file)
            #expect(link(file.path, package.appendingPathComponent(UUID().uuidString.lowercased()).path) == 0)
        case "nested": try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        default: break
        }
        let parent = try fixture.open(), sources = try parent.openSources()
        var replaced = false
        await #expect(throws: (any Error).self) {
            try await sources.visitPhotoEntries { entry in
                if change == "replacement", !replaced, entry.token.split(separator: "/").count == 3 {
                    replaced = true
                    try FileManager.default.moveItem(at: package, to: fixture.parent.deletingLastPathComponent().appendingPathComponent("preserved-package"))
                    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
                }
            }
        }
        try sources.check() // Failure never invalidates or repairs the fixed roots.
    }

    @Test(arguments: [false, true])
    func openerRetainsExactStoreFenceAndRechecksOuterAndRuntimeScopes(deletion: Bool) throws {
        let fixture = try Fixture(deletion: deletion), parent = try fixture.open()
        try parent.check()
        #expect(throws: (any Error).self) { _ = try fixture.admission.acquireFence(container: fixture.container) }
        fixture.runtimeCurrent = false
        #expect(throws: (any Error).self) { try parent.check() }
        fixture.runtimeCurrent = true; try parent.check()
        fixture.scopeCurrent = false
        #expect(throws: (any Error).self) { try parent.check() }
    }

    @Test func terminalCandidateReplacementDuringRevalidationFails() throws {
        let fixture = try Fixture(), parent = try fixture.open(), receipt = try fixture.terminal(parent)
        try fixture.write(receipt)
        var checkpoints = 0
        fixture.runtimeHook = { [weak fixture] in
            checkpoints += 1
            // The first check brackets the candidate read. Revoke its bytes
            // on the subsequent scope revalidation, before Tree's readback.
            if checkpoints == 3 {
                let changed = Data([1])
                let path = try #require(fixture?.parent.path)
                #expect(changed.withUnsafeBytes {
                    setxattr(path, SharedMediaNativeErasureTerminalReceipt.marker, $0.baseAddress, $0.count, 0, 0)
                } == 0)
            }
        }
        #expect(throws: (any Error).self) { _ = try parent.recoverTerminal() }
        #expect(checkpoints >= 3)
    }

    @Test(arguments: ["missingReceipt", "foreignReceipt", "unknownFile", "parentReplacement"])
    func changedParentCannotOpenOrContinue(change: String) throws {
        let fixture = try Fixture()
        var parent: SharedMediaNativeErasureParent? = try fixture.open()
        switch change {
        case "missingReceipt": try FileManager.default.removeItem(at: fixture.receiptURL)
        case "foreignReceipt": try Data([1]).write(to: fixture.receiptURL)
        case "unknownFile": try Data([2]).write(to: fixture.parent.appendingPathComponent("unexpected"))
        default:
            try FileManager.default.moveItem(at: fixture.parent, to: fixture.parent.appendingPathExtension("moved"))
            try FileManager.default.createDirectory(at: fixture.parent, withIntermediateDirectories: false)
        }
        #expect(throws: (any Error).self) { try parent!.check() }
        parent = nil
        #expect(throws: (any Error).self) { _ = try fixture.open() }
    }

    @Test(arguments: [false, true])
    func terminalRecoveryUsesAcceptedOperationAndHeldStore(deletion: Bool) throws {
        let fixture = try Fixture(deletion: deletion), parent = try fixture.open()
        let receipt = try fixture.terminal(parent)
        try fixture.write(receipt)
        let terminal = try parent.recoverTerminal()
        try terminal.require(receipt.header, profile: receipt.profile)
        let context = ModelContext(fixture.container); context.autosaveEnabled = false
        context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: UUID(), inventoryGeneration: UUID()))
        try context.save()
        #expect(throws: (any Error).self) { _ = try parent.recoverTerminal() }
    }

    @Test(arguments: ["operation", "kind", "store", "storeFile", "storeParent", "controlParent", "receipt", "owner"])
    func terminalCandidateCannotSupplyItsOwnIndependentBindings(change: String) throws {
        let fixture = try Fixture(), parent = try fixture.open()
        let receipt = try fixture.terminal(parent)
        var object = try #require(JSONSerialization.jsonObject(with: receipt.encoded()) as? [String: Any])
        var header = try #require(object["header"] as? [String: Any])
        switch change {
        case "operation": header["operationID"] = UUID().uuidString
        case "kind": header["operation"] = "accountDeletion"
        case "storeFile": header["storeFileIdentity"] = "1:2"
        case "storeParent": header["storeParentIdentity"] = "1:2"
        case "controlParent": header["controlParentIdentity"] = "1:2"
        case "receipt": header["parentReceiptSHA256"] = String(repeating: "f", count: 64)
        default:
            var profile = try #require(object["profile"] as? [String: Any])
            profile[change == "owner" ? "ownerID" : "storeIdentity"] = UUID().uuidString
            object["profile"] = profile
            let decoded = try JSONDecoder().decode(SharedMediaNativeAppProfile.self, from: JSONSerialization.data(withJSONObject: profile))
            header["profileSHA256"] = try SharedMediaAcquisitionEncoding.digest(decoded.binding)
        }
        object["header"] = header
        let changed = try JSONDecoder().decode(SharedMediaNativeErasureTerminalReceipt.self,
            from: JSONSerialization.data(withJSONObject: object))
        try fixture.write(changed)
        #expect(throws: (any Error).self) { _ = try parent.recoverTerminal() }
    }

    @Test func newSameOwnerOperationCannotContinueOldReceipt() throws {
        let fixture = try Fixture(), parent = try fixture.open()
        try fixture.write(fixture.terminal(parent))
        fixture.journal = LibrarySignOutJournal(sourceUserID: fixture.ownerID)
        fixture.journal.phase = .sourceCleared
        #expect(throws: (any Error).self) { _ = try parent.recoverTerminal() }
    }

    @MainActor private final class Fixture {
        let container: ModelContainer, admission: NativeReleaseStartupAdmission, ownerID: UUID
        let parent: URL
        var receiptURL: URL { parent.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentReceiptName) }
        var journal: LibrarySignOutJournal
        var operationID: UUID { deletion ? deletionMarker.operationID : journal.cleanupOperationID! }
        let deletion: Bool
        let deletionMarker = AccountDeletionCleanupMarker(phase: .cleanupPending, operationID: UUID())
        var scopeCurrent = true, runtimeCurrent = true
        var runtimeHook: (() throws -> Void)?
        private var authorization: SharedMediaNativeErasureAuthorization!

        init(deletion: Bool = false, createParent: Bool = true) throws {
            self.deletion = deletion
            let original = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true)
            let startup = try original.startup()
            container = startup.0; admission = startup.1; ownerID = original.ownerID
            let support = original.parent.deletingLastPathComponent()
            parent = support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName)
            journal = .init(sourceUserID: ownerID); journal.phase = .sourceCleared
            if createParent {
                let discovery = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: container,
                    admission: admission, support: support, ownerID: ownerID)
                discovery.invalidate()
            }
            if deletion {
                let marker = deletionMarker, library = container
                let scope = AccountDeletionLocalCleanupStore.RecoveryScope(expectedState: .cleanupPending,
                    expectedCapability: nil, capabilityStore: .init(secureStore: AccountDeletionSecureStoreStub()),
                    readState: { .cleanupPending }, validateSession: { [weak self] in self?.scopeCurrent == true },
                    validateLibrary: { $0 == nil || $0 === library }, expectedMarker: marker, readMarker: { marker })
                authorization = .accountDeletion(scope)
            } else {
                let store = LibrarySignOutJournalStore(dependencies: .init(
                    read: { [weak self] in try self.map { try JSONEncoder().encode($0.journal) } },
                    write: { _ in false }, remove: {}))
                let candidate = store.recoveryScope(expected: journal, validateContext: { [weak self] in
                    self?.scopeCurrent == true
                })
                let scope = try #require(candidate)
                authorization = .signOut(scope)
            }
        }
        func open() throws -> SharedMediaNativeErasureParent {
            try .qualification(container: container, admission: admission, authorization: authorization,
                parent: parent, runtimeCheckpoint: { [weak self] in
                    guard self?.runtimeCurrent == true else { throw SharedMediaStorageFailure.stale }
                    try self?.runtimeHook?()
                })
        }
        func emptyProbe() throws -> SharedMediaNativeErasureEmptyProbe? {
            try .qualification(container: container, admission: admission, authorization: authorization,
                support: parent.deletingLastPathComponent(), runtimeCheckpoint: { [weak self] in
                    guard self?.runtimeCurrent == true else { throw SharedMediaStorageFailure.stale }
                })
        }
        func deletionScope() throws -> AccountDeletionLocalCleanupStore.RecoveryScope {
            guard case .accountDeletion(let scope) = authorization else { throw SharedMediaStorageFailure.closed }
            return scope
        }
        func historyDocuments() throws -> URL {
            let documents = parent.deletingLastPathComponent().appendingPathComponent("HistoryDocuments")
            for name in ["ReanalysisQueue", "ReanalysisInputs"] {
                let directory = documents.appendingPathComponent(name).appendingPathComponent(UUID().uuidString.lowercased())
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data([1, 2, 3]).write(to: directory.appendingPathComponent("synthetic.bin"))
            }
            return documents
        }
        func coordinator(documents: URL, defaults: UserDefaults,
                         beforeHistory: @escaping @MainActor () async throws -> Void,
                         resetRuntime: @escaping @MainActor () -> Void) throws -> AppDIContainer {
            let di = AppDIContainer.preview
            di.offlineQueueManager.modelContext = ModelContext(container)
            try di.nativeMediaLifecycle.configureNativeMediaForTesting(container: container, admission: admission)
            try di.nativeMediaLifecycle.libraryCleanup.configureErasureForTesting(support: parent.deletingLastPathComponent(),
                documents: documents, defaults: defaults, beforeHistoryErasure: beforeHistory, resetRuntime: resetRuntime)
            return di
        }
        func captureOriginals() async throws -> (partial: URL, final: URL) {
            let runtime = AuthRuntimeState()
            let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime)
            let discovery = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: container,
                admission: admission, support: parent.deletingLastPathComponent(), ownerID: ownerID)
            let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
            _ = try await owner.openApp(container: container, discovery: discovery)
            let bytes = Data(repeating: 7, count: 48), scan = UUID(), generation = UUID()
            func input(_ ordinal: Int) -> SharedMediaCaptureDraftSourceInput {
                .init(id: UUID(), scanID: scan, submissionGeneration: generation, mediaID: UUID(), itemIndex: ordinal,
                    role: .sourceAudio, contentType: "audio/wav", byteCount: Int64(bytes.count),
                    sha256: SharedMediaAcquisitionEncoding.digest(bytes), context: .init(origin: .microphone, cameraVerticalCenter: nil))
            }
            let ready = input(0), interrupted = input(1)
            _ = try await owner.materializeAppCaptureSource(ready, bytes: bytes)
            try owner.configureCaptureArtifactWritingForTesting { if $0 == .afterPartialCreation { throw Interruption.injected } }
            await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureSource(interrupted, bytes: bytes) }
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            let namespace = parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName)
                .appendingPathComponent(SharedMediaCaptureRootJournal.childName)
            return (namespace.appendingPathComponent(interrupted.id.uuidString.lowercased() + ".partial"),
                namespace.appendingPathComponent(ready.id.uuidString.lowercased()))
        }
        func requireNormalCaptureInspectionClosed() async throws {
            let parent = try open(), sources = try parent.openSources()
            let files = try #require(try sources.captureFiles())
            await #expect(throws: SharedMediaStorageFailure.closed) {
                try await SharedMediaCaptureArtifactInspection.withVerified(container: container, profile: sources.profile,
                    files: files, checkpoint: { try sources.check() }) { _ in Issue.record("Normal admission accepted an unreceipted empty partial") }
            }
        }
        func photoOriginals(received: Bool, reserve: Bool = true) async throws -> (partial: URL, final: URL) {
            let runtime = AuthRuntimeState()
            let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime)
            let discovery = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: container,
                admission: admission, support: parent.deletingLastPathComponent(), ownerID: ownerID)
            let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
            _ = try await owner.openApp(container: container, discovery: discovery)
            let package = UUID(), draft = UUID(), bytes = PhotoPreparationTestHarness.image()
            let request = try await owner.prepareAppOriginal(packageID: package, draftGeneration: draft, ordinal: 0, kind: .picker)
            let acquired = try await owner.acquireAppOriginal(request) { bytes }
            let original = PhotoOriginalReference(ownerID: ownerID, packageID: package, referenceID: request.referenceID,
                assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: draft,
                referenceRevision: acquired.referenceRevision)
            let ready = try await owner.prepareAndDeliverAppPhoto(original: original, recipe: .init(format: .stillImage,
                isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
            let metadata = try await owner.prepareAppMetadata(packageID: package, draftGeneration: draft,
                contexts: [.init(freeText: "Synthetic cleanup context")])
            _ = try await owner.saveAppMetadata(metadata)
            let prepared = try await owner.stageAppReceiving(packageID: package, draftGeneration: draft,
                pairIDs: [try ready.intent().pairID])
            if received { _ = try await owner.receiveAppPrepared(prepared) }
            let pending = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
            if reserve {
                // Preparing a request alone reserves nothing. Exercise the real
                // reservation and failed-loader settlement before crash bytes.
                await #expect(throws: (any Error).self) {
                    _ = try await owner.acquireAppOriginal(pending) { throw Interruption.injected }
                }
                let context = ModelContext(container), id = pending.operationID, assetID = pending.assetID
                let row = try #require(try context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first)
                #expect(try SharedMediaAcquisitionReceipt.read(row, expected: pending) == .held(pending))
                let lease = try #require(try context.fetch(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })).first)
                #expect(lease.terminalProof == nil && lease.assetID == assetID)
                let allocation = try #require(try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })).first)
                #expect(allocation.fileToken == pending.finalToken && allocation.stateRaw == "p1Held")
                #expect(allocation.reservedBytes == pending.maximumBytes && allocation.materializedBytes == 0)
            }
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            let namespace = parent.appendingPathComponent("photo/PhotoPreparation")
            let partial = namespace.appendingPathComponent(pending.partialToken)
            try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Crash fixture: typed reservation survived but the process never
            // wrote a terminalProof for its bounded partial bytes.
            try Data(bytes.prefix(32)).write(to: partial)
            return (partial, namespace.appendingPathComponent(request.finalToken))
        }
        func prepareSources(capture: SharedMediaCaptureRootBoundary? = nil) async throws -> SharedMediaNativeAppProfile {
            var stage = "discovery"
            do {
                let runtime = AuthRuntimeState()
                let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime)
                let discovery = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: container,
                    admission: admission, support: parent.deletingLastPathComponent(), ownerID: ownerID)
                let owner = try SharedMediaNativeOriginalOwner.appInitialization(account: account, drain: .init())
                stage = "initialization"
                _ = try await owner.initializeApp(container: container, parent: discovery.parent,
                    inventoryID: discovery.inventoryID, discovery: discovery)
                #expect(await owner.invalidateAndAwaitForAccountTransition())
                stage = "rediscovery"
                let next = try SharedMediaNativeBootstrapDiscovery.qualificationStartup(container: container,
                    admission: admission, support: parent.deletingLastPathComponent(), ownerID: ownerID)
                let profile = try #require(next.existingProfile)
                if let capture {
                    let reader = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
                    stage = "dispatch"
                    _ = try await reader.openApp(container: container, parent: next.parent, inventoryID: next.inventoryID, discovery: next)
                    try reader.configureCaptureRootRecoveryForTesting { if $0 == capture { throw Interruption.injected } }
                    await #expect(throws: Interruption.self) { _ = try await reader.recoverAppCaptureRoot() }
                    #expect(await reader.invalidateAndAwaitForAccountTransition())
                } else { next.invalidate() }
                return profile
            } catch { throw SetupFailure(stage: stage, underlying: error) }
        }
        func terminal(_ parent: SharedMediaNativeErasureParent, profile supplied: SharedMediaNativeAppProfile? = nil,
                      controlSHA256: String = String(repeating: "c", count: 64)) throws -> SharedMediaNativeErasureTerminalReceipt {
            let profile = supplied ?? SharedMediaNativeAppProfile(ownerID: ownerID, inventoryID: UUID(), generation: UUID(),
                storeIdentity: parent.storeIdentity, physicalBinding: String(repeating: "a", count: 64),
                receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: .physicalRootsV1)
            let context = ModelContext(container); context.autosaveEnabled = false
            let header = SharedMediaNativeErasureHeader(version: 1, operation: deletion ? .accountDeletion : .signOut,
                operationID: deletion ? deletionMarker.operationID : try #require(journal.cleanupOperationID),
                profileSHA256: try SharedMediaAcquisitionEncoding.digest(profile.binding), storeFileIdentity: parent.storeFileIdentity,
                storeParentIdentity: parent.storeParentIdentity, controlParentIdentity: parent.controlParentIdentity,
                parentReceiptSHA256: parent.parentReceiptSHA256, controlSHA256: controlSHA256,
                sourceRevision: 0, sourceTables: try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: {}),
                pageCount: 1, entryCount: 1, lastPageSHA256: String(repeating: "d", count: 64))
            return .init(version: 1, profile: profile, header: header)
        }
        func write(_ receipt: SharedMediaNativeErasureTerminalReceipt) throws {
            let bytes = try receipt.encoded()
            #expect(bytes.withUnsafeBytes {
                setxattr(parent.path, SharedMediaNativeErasureTerminalReceipt.marker, $0.baseAddress, $0.count, 0, 0)
            } == 0)
        }
    }
}
