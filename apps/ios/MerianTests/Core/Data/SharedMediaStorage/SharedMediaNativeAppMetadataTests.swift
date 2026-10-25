import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app metadata transactions", .serialized)
@MainActor
struct SharedMediaNativeAppMetadataTests {
    @Test func exactEditPreservesOrdinaryDraftsAndAcknowledgesWithoutAnotherSave() async throws {
        let h = try Store(), owner = try await h.open()
        let before = try await owner.inspectApp(), member = try h.memberBytes()
        let request = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "Observed under a leaf")])
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        #expect(try await owner.saveAppMetadata(request) == 1)
        #expect(try await owner.saveAppMetadata(request) == 1)
        #expect(saves == 1)
        let after = try await owner.inspectApp()
        #expect(after.inventory.revision == before.inventory.revision + 1)
        #expect(after.pendingPackages == 1 && after.allocations == 0 && after.consumers == 0)
        #expect(try h.memberBytes() == member)
        #expect(try h.package().supportingContextData == request.envelope)
        let ordinary = try h.package(h.ordinaryID)
        #expect(ordinary.supportingContextData == Data("ordinary-draft".utf8) && ordinary.phaseRaw == "preparing" && ordinary.revision == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["bootstrap", "inventory", "package", "member", "missingMember", "owner"])
    func staleRequestsNeverRebaseOrSave(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open()
        let request = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [])
        let context = h.context()
        switch fault {
        case "bootstrap": try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).revision += 1
        case "inventory": try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1
        case "package": try h.package(in: context).revision += 1
        case "member": try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1
        case "missingMember": context.delete(try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first))
        default: try h.package(in: context).ownerID = UUID()
        }
        try context.save()
        let before = try h.package().supportingContextData
        await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(request) }
        #expect(try h.package().supportingContextData == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "readbackLoss"])
    func faultsDoNotRepeatAnUncertainSave(_ point: String) async throws {
        let h = try Store(), owner = try await h.open()
        let request = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "Preserve this exact draft")])
        var saves = 0
        try owner.setMetadataFault { boundary in
            if boundary == .beforeSave { saves += 1 }
            if (point == "beforeSave" && boundary == .beforeSave) || (point == "afterSave" && boundary == .afterSave)
                || (point == "readbackLoss" && boundary == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if point == "afterSave" { #expect(try await owner.saveAppMetadata(request) == 1) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(request) } }
        let persisted = try h.package()
        #expect(persisted.revision == (point == "beforeSave" ? 0 : 1))
        #expect(saves == 1)
        if point != "beforeSave" {
            try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
            #expect(try await owner.saveAppMetadata(request) == 1)
            #expect(saves == 1)
            #expect(try h.package().supportingContextData == request.envelope)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["bootstrap", "package", "member"])
    func preSaveFreshRecheckRejectsDrift(_ target: String) async throws {
        let h = try Store(), owner = try await h.open()
        let request = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "Must not replace drift")])
        try owner.setMetadataFault { point in
            guard point == .beforeSave else { return }
            let context = h.context()
            if target == "bootstrap" { try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).revision += 1 }
            else if target == "package" { try h.package(in: context).revision += 1 }
            else { try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1 }
            try context.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(request) }
        #expect(try h.package().supportingContextData == request.package.envelope)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func ordinaryAndRetiredOwnerCannotUseNativeMetadataPath() async throws {
        let h = try Store(), owner = try await h.open()
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAppMetadata(packageID: h.ordinaryID, draftGeneration: UUID(), contexts: []) }
        let request = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [])
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(request) }
        #expect(try h.package().revision == 0)
    }

    @Test(arguments: ["extraUpdate", "insert", "delete", "missingUpdate"])
    func exactWriteSetRejectsOtherChanges(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open()
        let context = h.context(), package = try h.package(in: context)
        let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        package.revision += 1; inventory.revision += 1
        try SharedMediaNativeAppMetadataFacts.requireWriteSet(context, inventory: inventory.persistentModelID, package: package.persistentModelID)
        switch fault {
        case "extraUpdate": try h.package(h.ordinaryID, in: context).revision += 1
        case "insert": context.insert(h.row(UUID(), envelope: Data(), phase: "draftOwned"))
        case "delete": context.delete(try h.package(h.ordinaryID, in: context))
        default: context.rollback(); package.revision += 1
        }
        #expect(throws: (any Error).self) {
            try SharedMediaNativeAppMetadataFacts.requireWriteSet(context, inventory: inventory.persistentModelID, package: package.persistentModelID)
        }
        context.rollback()
        #expect(try h.package().revision == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func oversizedContextAndDirtyMainContextFailWithoutSaving() async throws {
        let h = try Store(), owner = try await h.open()
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
                contexts: [.init(freeText: String(repeating: "x", count: 100_000))])
        }
        h.container.mainContext.insert(h.row(UUID(), envelope: Data(), phase: "draftOwned"))
        await #expect(throws: (any Error).self) { _ = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: []) }
        #expect(h.container.mainContext.hasChanges)
        h.container.mainContext.rollback()
        #expect(try h.package().revision == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func validPendingConsumerCoexistsAndPreSaveDriftBlocksBothUpdates(_ drift: Bool) async throws {
        let h = try Store(receiving: true), (owner, consumerID) = try await h.openWithReceivingConsumer()
        let context = h.context()
        let consumer = try #require(try SharedMediaConsumerLookup.one(context, id: consumerID))
        let exactConsumer = SharedMediaNativeAppMetadataFacts.Consumer(consumer)
        let before = try await owner.inspectApp()
        #expect(before.pendingPackages == 2 && before.consumers == 1)
        // Frozen/submitted supporting content cannot become an editable draft.
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareAppMetadata(packageID: consumer.packageID, draftGeneration: consumer.draftGeneration, contexts: [])
        }
        let request = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: [.init(freeText: "Independent pending draft")])
        if drift {
            try owner.setMetadataFault { point in
                guard point == .beforeSave else { return }
                let fresh = h.context()
                let row = try #require(try SharedMediaConsumerLookup.one(fresh, id: consumerID))
                row.revision += 1; try fresh.save()
            }
            await #expect(throws: (any Error).self) { _ = try await owner.saveAppMetadata(request) }
            #expect(try h.package().revision == request.package.revision)
            #expect(try h.package().supportingContextData == request.package.envelope)
            let inventory = try #require(try h.context().fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            #expect(inventory.revision == before.inventory.revision)
        } else {
            #expect(try await owner.saveAppMetadata(request) == 1)
            let after = try await owner.inspectApp()
            #expect(after.inventory.revision == before.inventory.revision + 1)
            #expect(after.pendingPackages == 2 && after.consumers == 1)
            let fresh = try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID))
            #expect(SharedMediaNativeAppMetadataFacts.Consumer(fresh) == exactConsumer)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["cohort", "execution", "retirement", "identity"])
    func pendingConsumerSnapshotsDetectExactScalarAndByteDrift(_ change: String) async throws {
        let h = try Store(), owner = try await h.open()
        let context = h.context()
        let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        // A scalar fact comparison only; this does not qualify a receiving cohort.
        let row = SharedMediaConsumerRecord(id: UUID(), kindRaw: "queue", consumerID: "test-queue", originQueueID: "test-queue",
            observationID: "test-observation", inventoryID: h.inventoryID, inventoryGeneration: inventory.generation,
            ownerID: h.ownerID, packageID: h.packageID, draftGeneration: h.draft, frozenPackageRevision: 0,
            contractVersion: "test-only", digestVersion: 2, cohortSHA256: "test-only", executionKindRaw: "initial", inferenceGeneration: nil)
        row.cohortData = Data("exact-test-cohort".utf8)
        let original = SharedMediaNativeAppMetadataFacts.Consumer(row)
        switch change {
        case "cohort": row.cohortData = Data("different-test-cohort".utf8)
        case "execution": row.inferenceGeneration = UUID()
        case "retirement": row.retirementID = UUID()
        default: row.consumerID = "different-queue"
        }
        #expect(SharedMediaNativeAppMetadataFacts.Consumer(row) != original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @MainActor struct Store {
        let container: ModelContainer, parent: URL
        let ownerID = UUID(), inventoryID = UUID(), packageID = UUID(), ordinaryID = UUID(), draft = UUID()
        let runtime = AuthRuntimeState()
        init(receiving: Bool = false, fenceBootstrap: Bool = false) throws {
            let base = URL.applicationSupportDirectory.resolvingSymlinksInPath().appendingPathComponent("native-app-metadata-" + UUID().uuidString)
            parent = base.appendingPathComponent("control", isDirectory: true)
            // V1 qualification requires a disposable temporary store and sibling
            // fixture roots. V2 still uses its real Application Support control
            // roots and pins this same SQLite store's identity and parent.
            let databaseBase = receiving ? FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("native-app-metadata-" + UUID().uuidString, isDirectory: true) : base
            let database = databaseBase.appendingPathComponent("database", isDirectory: true)
            for directory in [parent, database] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var url = directory, values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
            }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let configuration = ModelConfiguration(schema: schema,
                url: database.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)
            // The opt-in process-exit control qualifies construction under the
            // same store fence used by its separate readback. Other fixtures
            // retain their existing behavior; no production entry is changed.
            let fence = try fenceBootstrap ? SharedMediaStoreReadFence(store: configuration.url, access: .sharedWriter) : nil
            container = try withExtendedLifetime(fence) {
                try ModelContainer(for: schema, configurations: [configuration])
            }
        }
        func context() -> ModelContext { let value = ModelContext(container); value.autosaveEnabled = false; return value }
        func row(_ id: UUID, envelope: Data, phase: String) -> PhotoPreparationRecord {
            .init(id: id, ownerID: ownerID, contractVersion: PhotoPreparationPolicy.contract, draftID: id,
                draftGeneration: draft, revision: 0, phaseRaw: phase, supportingContextData: envelope, allocatedByteCount: 0, retirementRequested: false)
        }
        func open() async throws -> SharedMediaNativeOriginalOwner {
            let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime)
            let bootstrap = try SharedMediaNativeOriginalOwner.appInitialization(account: account, drain: .init())
            let snapshot = try await bootstrap.initializeApp(container: container, parent: parent, inventoryID: inventoryID)
            #expect(await bootstrap.invalidateAndAwaitForAccountTransition())
            // Test-only seeding keeps metadata tests focused on existing drafts.
            // Fresh drafts are created by the native acquisition owner.
            let context = context()
            context.insert(row(packageID, envelope: try PhotoPreparationPolicy.encodeDraft(contexts: [], presentation: []), phase: "draftOwned"))
            context.insert(SharedMediaPendingMembershipRecord(packageID: packageID, inventoryID: inventoryID,
                inventoryGeneration: snapshot.generation, ownerID: ownerID, draftGeneration: draft,
                membersData: try SharedMediaMembership(groups: []).encoded()))
            context.insert(row(ordinaryID, envelope: Data("ordinary-draft".utf8), phase: "preparing"))
            try context.save()
            let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
            _ = try await owner.openApp(container: container, parent: parent, inventoryID: inventoryID)
            return owner
        }
        func openWithReceivingConsumer() async throws -> (SharedMediaNativeOriginalOwner, UUID) {
            let initial = try await open()
            #expect(await initial.invalidateAndAwaitForAccountTransition())
            let context = context()
            let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            let app = try SharedMediaNativeAppEligibility.profile(inventory)
            // Synthetic test data only: retain the real V2 control files while
            // using the proven V1 producer to build a valid frozen consumer in
            // this same disposable store. No runtime conversion is exposed.
            for row in try context.fetch(FetchDescriptor<PhotoPreparationRecord>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) { context.delete(row) }
            context.delete(inventory); try context.save()
            let databaseURL = try #require(container.configurations.first).url
            let h = try SharedMediaNativePreparationTests.Harness(base: databaseURL.deletingLastPathComponent().deletingLastPathComponent(),
                container: container, inventoryID: inventoryID, ownerID: ownerID, packageID: UUID(), draft: UUID())
            let empty = try await h.open(); #expect(await empty.invalidateAndAwaitForAccountTransition())
            let seed = self.context()
            try #require(try seed.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).generation = app.generation
            try #require(try seed.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).inventoryGeneration = app.generation
            try seed.save()
            let (_, consumerID) = try await SharedMediaNativeConsumerGraphTests().fixture(h)
            let restore = self.context()
            let row = try #require(try restore.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            row.modeRaw = SharedMediaNativeAppProfile.mode; row.phaseRaw = SharedMediaNativeAppProfile.phase
            row.rootIdentity = try app.rootIdentity
            try #require(try restore.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).contractVersion = 2
            restore.insert(self.row(packageID, envelope: try PhotoPreparationPolicy.encodeDraft(contexts: [], presentation: []), phase: "draftOwned"))
            restore.insert(SharedMediaPendingMembershipRecord(packageID: packageID, inventoryID: inventoryID,
                inventoryGeneration: app.generation, ownerID: ownerID, draftGeneration: draft,
                membersData: try SharedMediaMembership(groups: []).encoded()))
            restore.insert(self.row(ordinaryID, envelope: Data("ordinary-draft".utf8), phase: "preparing"))
            try restore.save()
            let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: ownerID, runtime: runtime), drain: .init())
            _ = try await owner.openApp(container: container, parent: parent, inventoryID: inventoryID)
            return (owner, consumerID)
        }
        func package(_ id: UUID? = nil, in context: ModelContext? = nil) throws -> PhotoPreparationRecord {
            let key = id ?? packageID
            return try #require(try (context ?? self.context()).fetch(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == key })).first)
        }
        func memberBytes() throws -> Data { try #require(try context().fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).membersData }
    }
}
