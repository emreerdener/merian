import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native original atomic acquisition", .serialized)
@MainActor
struct SharedMediaNativeAcquisitionOwnerTests {
    @Test func exactOriginalAndTwoSlotsSurviveRestartWithoutLoadingAgain() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let package = UUID(), draft = UUID(), loader = Loader()
        let first = try await owner.prepareOriginal(packageID: package, draftGeneration: draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        let result = try await owner.acquireOriginal(first) { await loader.load(bytes) }
        #expect(try Data(contentsOf: h.file(first)) == bytes)
        #expect(result.inventoryRevision == 2 && result.packageRevision == 1 && result.membershipRevision == 1)
        let second = try await owner.prepareOriginal(packageID: package, draftGeneration: draft, ordinal: 1, kind: .camera)
        let secondResult = try await owner.acquireOriginal(second) { await loader.load(bytes) }
        #expect(secondResult.inventoryRevision == 4 && secondResult.packageRevision == 3 && secondResult.membershipRevision == 3)
        let replay = try await owner.acquireOriginal(first) { await loader.load(Data()) }
        #expect(replay == result)
        #expect(await loader.calls == 2)
        try h.audit()
        #expect(await h.drain.shutdown())
        let restarted = try h.owner(drain: .init()); _ = try await h.open(restarted)
        #expect(try await restarted.acquireOriginal(first) { await loader.load(Data()) } == result)
        #expect(await loader.calls == 2)
        #expect(await restarted.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeReservationSave", "afterReservationSave", "beforeCompletionSave", "afterCompletionSave"])
    func saveAcknowledgementsNeverRepeatLoader(_ boundary: String) async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        var injected = false
        try owner.setAcquisitionFault { point in
            if !injected && String(describing: point) == boundary { injected = true; throw Fault.injected }
        }
        if boundary == "afterReservationSave" || boundary == "afterCompletionSave" {
            let result = try await owner.acquireOriginal(request) { await loader.load(bytes) }
            #expect(try await owner.acquireOriginal(request) { await loader.load(Data()) } == result)
            #expect(await loader.calls == 1)
        } else {
            await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { await loader.load(bytes) } }
            if boundary == "beforeReservationSave" {
                #expect(try h.receipt(request) == nil)
                #expect(await loader.calls == 0)
                #expect(try h.inventoryRevision() == 0)
            } else {
                #expect(try h.receipt(request) == .held(request))
                #expect(try Data(contentsOf: h.file(request)) == bytes)
                await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { await loader.load(bytes) } }
                #expect(await loader.calls == 1)
                try h.assertHeld(request)
            }
        }
        #expect(injected)
        try h.audit(); #expect(await h.drain.shutdown())
    }

    @Test(arguments: ["beforeHeldSave", "afterHeldSave"])
    func heldSaveRecoveryRetainsCapacityAndAllowsExplicitDrainRetry(_ boundary: String) async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), loader = Loader()
        try owner.setAcquisitionFault { point in
            if String(describing: point) == boundary { throw Fault.injected }
        }
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { await loader.load(Data()) } }
        if boundary == "beforeHeldSave" {
            #expect(!(await h.drain.shutdown()))
            #expect(try h.receipt(request) == .reserved(request))
            let competing = try h.owner(drain: .init())
            await #expect(throws: (any Error).self) { try await h.open(competing) }
            try owner.setAcquisitionFault(nil)
        }
        #expect(await h.drain.shutdown())
        try h.assertHeld(request); try h.audit()
        let cold = try h.owner(drain: .init())
        #expect(try await h.open(cold).requiresRecovery)
        await #expect(throws: (any Error).self) { try await cold.acquireOriginal(request) { await loader.load(Data()) } }
        await #expect(throws: (any Error).self) { try await h.request(cold) }
        #expect(await loader.calls == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func unknownCompletionReadbackBlocksDrainUntilExactSettlement() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        var unavailable = false
        try owner.setAcquisitionFault { point in
            if point == .afterCompletionSave { unavailable = true; throw Fault.injected }
            if point == .beforeReadback && unavailable { throw Fault.injected }
        }
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { await loader.load(bytes) } }
        // Unresolved settlement revokes ordinary reads as well as new work.
        await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.snapshot() }
        await #expect(throws: SharedMediaStorageFailure.closed) { try await h.request(owner) }
        #expect(!(await h.drain.shutdown()))
        #expect(await loader.calls == 1)
        let saved = try #require(try h.receipt(request))
        guard case .completed(_, let result) = saved else { Issue.record("Completion must win"); return }
        try owner.setAcquisitionFault(nil)
        #expect(await h.drain.shutdown())
        let cold = try h.owner(drain: .init()); _ = try await h.open(cold)
        #expect(try await cold.acquireOriginal(request) { await loader.load(Data()) } == result)
        #expect(await loader.calls == 1)
        #expect(try h.inventoryRevision() == 2)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func accountDrainWaitsForUncancellableLoaderThenPersistsHeld() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), gate = Gate(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let task = Task {
            do { return try await owner.acquireOriginal(request) { await gate.hold(); return await loader.load(bytes) } } catch { await gate.failedBeforeEntry(); throw error }
        }
        guard await gate.waitForEntry() else {
            _ = await task.result; _ = await h.drain.shutdown(); throw Fault.loaderDidNotStart
        }
        do {
            var finished = false
            let teardown = Task { let value = await h.drain.shutdown(); finished = true; return value }
            await Task.yield()
            #expect(!finished && h.work.active == 1)
            let competing = try h.owner(drain: .init())
            await #expect(throws: (any Error).self) { try await h.open(competing) }
            await gate.release()
            await #expect(throws: (any Error).self) { try await task.value }
            #expect(await teardown.value)
            #expect(h.work.active == 0)
            #expect(await loader.calls == 1)
            try h.assertHeld(request); try h.audit()
            #expect(!FileManager.default.fileExists(atPath: h.file(request).path))
        } catch {
            await gate.release(); _ = await task.result; _ = await h.drain.shutdown(); throw error
        }
    }

    @Test func missingReceiptAfterWriterReturnsCannotReleaseOwnership() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        try owner.setAcquisitionFault { point in
            guard point == .afterOriginalWrite else { return }
            let context = ModelContext(h.container); context.autosaveEnabled = false
            let id = request.operationID
            let row = try #require(try context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first)
            context.delete(row); try context.save()
        }
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { await loader.load(bytes) } }
        #expect(await loader.calls == 1)
        #expect(try Data(contentsOf: h.file(request)) == bytes)
        #expect(try h.receipt(request) == nil)
        #expect(!(await h.drain.shutdown()))
        #expect(h.work.active == 0)
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { await loader.load(bytes) } }
        let competitor = try h.owner(drain: .init())
        await #expect(throws: (any Error).self) { try await h.open(competitor) }
        #expect(await loader.calls == 1)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 1)
    }

    @Test func staleRequestAndMissingMediaNeverInvokeLoader() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let first = try await h.request(owner), stale = try await h.request(owner), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireOriginal(first) { await loader.load(bytes) }
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(stale) { await loader.load(Data()) } }
        #expect(try h.receipt(stale) == nil)
        try FileManager.default.removeItem(at: h.file(first))
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(first) { await loader.load(Data()) } }
        #expect(await loader.calls == 1)
        #expect(try h.inventoryRevision() == 2)
        #expect(await h.drain.shutdown())
    }

    @Test func unchangedPendingPackageLimitRejectsBeforeLoading() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        for _ in 0..<4 {
            let request = try await h.request(owner)
            _ = try await owner.acquireOriginal(request) { await loader.load(bytes) }
        }
        let denied = try await h.request(owner)
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(denied) { await loader.load(bytes) } }
        #expect(await loader.calls == 4)
        #expect(try h.receipt(denied) == nil)
        #expect(try h.inventoryRevision() == 8)
        try h.audit(); #expect(await h.drain.shutdown())
    }

    @Test func changedIntentCannotReplayOrReserveAnotherAccount() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireOriginal(request) { await loader.load(bytes) }
        for foreign in [false, true] {
            let changed = SharedMediaAcquisitionIntent(operationID: request.operationID, inventoryID: request.inventoryID,
                inventoryGeneration: request.inventoryGeneration, ownerID: foreign ? UUID() : request.ownerID,
                expectedInventoryRevision: request.expectedInventoryRevision, packageID: request.packageID,
                draftGeneration: request.draftGeneration, packageExpectation: request.packageExpectation,
                assetID: request.assetID, assetGeneration: request.assetGeneration, referenceID: request.referenceID,
                ordinal: foreign ? request.ordinal : 1, kind: request.kind, writerEpoch: request.writerEpoch, maximumBytes: request.maximumBytes)
            await #expect(throws: (any Error).self) { try await owner.acquireOriginal(changed) { await loader.load(bytes) } }
        }
        #expect(await loader.calls == 1)
        #expect(try h.inventoryRevision() == 2)
        try h.audit(); #expect(await h.drain.shutdown())
    }

    @Test(arguments: ["inventory", "package"])
    func changedReservationDuringLoaderCannotRebaseOrWrite(_ changed: String) async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), gate = Gate(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let task = Task {
            do { return try await owner.acquireOriginal(request) { await gate.hold(); return await loader.load(bytes) } } catch { await gate.failedBeforeEntry(); throw error }
        }
        guard await gate.waitForEntry() else {
            _ = await task.result; _ = await h.drain.shutdown(); throw Fault.loaderDidNotStart
        }
        do {
            let context = ModelContext(h.container); context.autosaveEnabled = false
            if changed == "inventory" {
                let row = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first); row.revision += 1
            } else {
                let row = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first); row.revision += 1
            }
            try context.save(); await gate.release()
            await #expect(throws: (any Error).self) { try await task.value }
            #expect(await loader.calls == 1)
            #expect(!FileManager.default.fileExists(atPath: h.file(request).path))
            #expect(try h.receipt(request) == .held(request))
            try h.audit(); #expect(await h.drain.shutdown())
        } catch {
            await gate.release(); _ = await task.result; _ = await h.drain.shutdown(); throw error
        }
    }

    @Test(arguments: ["inventory", "package"])
    func changedReservationAfterWriteRetainsOriginalWithoutCompleting(_ changed: String) async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        var injected = false
        try owner.setAcquisitionFault { point in
            guard point == .afterOriginalWrite else { return }
            injected = true
            let context = ModelContext(h.container); context.autosaveEnabled = false
            if changed == "inventory" {
                let row = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first); row.revision += 1
            } else {
                let row = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first); row.revision += 1
            }
            try context.save()
        }
        await #expect(throws: (any Error).self) { try await owner.acquireOriginal(request) { await loader.load(bytes) } }
        #expect(injected)
        #expect(try h.receipt(request) == .held(request))
        #expect(await loader.calls == 1)
        #expect(try Data(contentsOf: h.file(request)) == bytes)
        try h.audit(); #expect(await h.drain.shutdown())
    }

    @Test func loaderGateReportsReservationFailureInsteadOfWaiting() async throws {
        let h = try Harness()
        let owner = try h.owner(); _ = try await h.open(owner)
        let request = try await h.request(owner), gate = Gate(), loader = Loader()
        try owner.setAcquisitionFault { if $0 == .beforeReservationSave { throw Fault.injected } }
        let task = Task {
            do { return try await owner.acquireOriginal(request) { await gate.hold(); return await loader.load(Data()) } } catch { await gate.failedBeforeEntry(); throw error }
        }
        #expect(!(await gate.waitForEntry()))
        await gate.release()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(await loader.calls == 0)
        #expect(try h.receipt(request) == nil)
        #expect(await h.drain.shutdown())
    }

    private enum Fault: Error { case injected, loaderDidNotStart }
    private actor Loader {
        private(set) var calls = 0
        func load(_ bytes: Data) -> Data { calls += 1; return bytes }
    }
    private actor Gate {
        private var waiting: CheckedContinuation<Void, Never>?
        private var entry: CheckedContinuation<Bool, Never>?
        private var entered = false, failed = false
        func hold() async { await withCheckedContinuation { waiting = $0; entered = true; entry?.resume(returning: true); entry = nil } }
        func waitForEntry() async -> Bool {
            if entered { return true }
            if failed { return false }
            return await withCheckedContinuation { entry = $0 }
        }
        func failedBeforeEntry() { failed = true; entry?.resume(returning: false); entry = nil }
        func release() { waiting?.resume(); waiting = nil }
    }
    @MainActor private final class WorkCount { var active = 0 }
    @MainActor private struct Harness {
        let base: URL, authority: URL, photo: URL, inbox: URL
        let inventoryID = UUID(), ownerID = UUID()
        let container: ModelContainer
        let runtime = AuthRuntimeState(), drain = SharedMediaNativeOriginalDrain()
        let work = WorkCount()
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-acquisition-" + UUID().uuidString)
            print("NATIVE_ACQUISITION_FIXTURE " + base.path)
            authority = base.appendingPathComponent("authority"); photo = base.appendingPathComponent("photo"); inbox = base.appendingPathComponent("inbox")
            let database = base.appendingPathComponent("database")
            for root in [authority, photo, inbox, database] { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner(drain: SharedMediaNativeOriginalDrain? = nil) throws -> SharedMediaNativeOriginalOwner {
            let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime)
            return try .qualification(account: .init(ownerID: ownerID,
                begin: { let lease = try account.begin(); work.active += 1; return lease }, isCurrent: account.isCurrent,
                finish: { account.finish($0); work.active -= 1 }), drain: drain ?? self.drain)
        }
        func open(_ owner: SharedMediaNativeOriginalOwner) async throws -> SharedMediaNativeOriginalSnapshot {
            try await owner.open(container: container, authorityRoot: authority, photoRoot: photo, inboxRoot: inbox, inventoryID: inventoryID)
        }
        func request(_ owner: SharedMediaNativeOriginalOwner) async throws -> SharedMediaAcquisitionIntent {
            try await owner.prepareOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        }
        func receipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt? {
            let context = ModelContext(container); context.autosaveEnabled = false
            let id = request.operationID
            return try context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first.map {
                try SharedMediaAcquisitionReceipt.read($0, expected: request)
            }
        }
        func inventoryRevision() throws -> Int64 {
            try #require(ModelContext(container).fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision
        }
        func audit() throws { try SharedMediaNativeAcquisitionGraph.audit(context: ModelContext(container), inventoryID: inventoryID) }
        func assertHeld(_ request: SharedMediaAcquisitionIntent) throws {
            #expect(try receipt(request) == .held(request))
            let context = ModelContext(container)
            let allocation = try #require(context.fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
            let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
            #expect(allocation.reservedBytes == request.maximumBytes && allocation.materializedBytes == 0)
            #expect(member.revision == 0)
            #expect(try inventoryRevision() == 2)
        }
        func file(_ request: SharedMediaAcquisitionIntent) -> URL { photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(request.finalToken) }
        // Retain this unique fixture until the test process exits. Unlinking
        // a live ModelContainer's SQLite/WAL files corrupts cleanup diagnostics;
        // the evidence runner removes only paths emitted by this run after exit.
    }
}
