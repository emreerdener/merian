import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive receiving terminal reader and accounting", .serialized)
@MainActor
struct SharedMediaNativeReceivingTerminalReaderTests {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let ownerTests = SharedMediaNativeReceivingTerminalOwnerTests()

    @Test func rejectsCorruptFieldsAndExecutionAliases() async throws {
        let (h, owner, before) = try await ownerTests.fixture()
        let value = try await owner.finishAppRelease(before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let mutations: [(SharedMediaReceivingIntentRecord) -> Void] = [
            { $0.schemaVersion = 1 }, { $0.inventoryID = UUID() }, { $0.inventoryGeneration = UUID() },
            { $0.ownerID = UUID() }, { $0.draftGeneration = UUID() }, { $0.operationID = UUID() },
            { $0.phaseRaw = "releasing" }, { $0.revision += 1 }, { $0.preparedData = Data() },
            { $0.preparedSHA256 = String(repeating: "0", count: 64) }, { $0.resultData = Data() },
            { $0.resultSHA256 = nil }, { $0.releaseStartData = Data() }, { $0.releaseStartSHA256 = "x" }, { $0.allocationData = Data() }, { $0.allocationSHA256 = "x" }
        ]
        for mutate in mutations {
            let c = h.context(), row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
            mutate(row); try c.save()
            #expect(throws: (any Error).self) { _ = try ownerTests.terminal(h) }
            try restore(row, value); try c.save()
            #expect(try ownerTests.terminal(h).value == value)
        }
        for alias in [value.plan.queueID.uuidString.lowercased(), value.plan.queueID.uuidString.uppercased(), value.plan.observationID.uuidString] {
            let c = h.context(), row = OfflineQueuedScan(id: alias)
            c.insert(row); try c.save()
            #expect(throws: (any Error).self) { _ = try ownerTests.terminal(h) }
            c.delete(row); try c.save()
        }
        #expect(try ownerTests.terminal(h).value == value)
    }

    @Test func pagesHistoricalTerminalsWithoutCreatingPendingPackages() async throws {
        let testStarted = ContinuousClock.now
        func phase(_ label: String) {
            print("Terminal pagination \(label); elapsed \(testStarted.duration(to: .now))")
        }
        phase("phase 1: fixture")
        let (h, owner, before) = try await ownerTests.fixture()
        phase("phase 2: initial closure")
        let first = try await owner.finishAppRelease(before)
        // The same draft-generation fence in a different package is valid;
        // inference/execution IDs, unlike draft fences, remain exclusive.
        phase("phase 3: live prepared package")
        let liveID = UUID()
        let request = try await owner.prepareAppOriginal(packageID: liveID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        let acquired = try await owner.acquireAppOriginal(request) { image }
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: liveID, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft,
            referenceRevision: acquired.referenceRevision)
        let ready = try await owner.prepareAndDeliverAppPhoto(original: original,
            recipe: SharedMediaNativeOriginalDispositionSharingTests.recipe)
        let live = try await owner.stageAppReceiving(packageID: liveID, draftGeneration: h.draft,
            pairIDs: [ready.intent().pairID])
        let initialContext = h.context()
        let initialBudget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: initialContext,
            inventory: ownerTests.inventory(h, initialContext), ownerID: h.ownerID, format: .appV2)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        phase("phase 4: historical clones")
        let c = h.context()
        // Synthetic clones qualify the reader only. The first terminal above
        // uses the actual owner/physical cleanup path; clones confer no rights.
        for _ in 0..<SharedMediaStoragePolicy.pageSize {
            let value = try clone(first)
            let p = value.plan
            let row = SharedMediaReceivingIntentRecord(packageID: p.package.id, inventoryID: p.profile.inventoryID,
                inventoryGeneration: p.profile.generation, ownerID: p.profile.ownerID, draftGeneration: p.package.generation,
                operationID: p.operationID, preparedData: Data(), preparedSHA256: p.preparedSHA256)
            try restore(row, value); c.insert(row)
        }
        try c.save()
        phase("phase 5: full terminal scan")
        var count = 0
        var selected: [SharedMediaNativeReceivingTerminal.Snapshot] = []
        var following: SharedMediaNativeReceivingTerminal.Snapshot?
        let summary = try SharedMediaNativeTerminalScan.read(container: h.container, inventoryID: h.inventoryID) { value in
            count += 1
            if selected.count < SharedMediaStoragePolicy.pageSize { selected.append(value) }
            else { following = value }
        }
        #expect(count == SharedMediaStoragePolicy.pageSize + 1)
        #expect(summary.consumptionAdvances == Int64(count))
        phase("phase 6: pending roots and budget")
        let fresh = h.context(), inventory = try ownerTests.inventory(h, fresh)
        let roots = try SharedMediaNativeReceivingCleanGraph.pending(fresh, inventory: inventory)
        #expect(Set(roots.keys) == [live.package.id])
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: fresh, inventory: inventory, ownerID: h.ownerID, format: .appV2)
        var expected = initialBudget.totals
        try expected.includePhotoPhysical(materialized: summary.bytes - Int64(first.encoded().count), reserved: 0)
        #expect(budget.totals == expected && budget.metadataByPackage[live.package.id] != nil)
        phase("phase 7: historical identity audit")
        let terminal = try ownerTests.terminal(h)
        #expect(throws: (any Error).self) {
            try SharedMediaNativeTerminalIdentity.auditPage([terminal, terminal], live: roots, context: fresh)
        }
        #expect(throws: (any Error).self) {
            try SharedMediaNativeTerminalIdentity.auditPage(
                Array(repeating: terminal, count: SharedMediaStoragePolicy.pageSize + 1), live: roots, context: fresh)
        }
        try SharedMediaNativeTerminalIdentity.audit(terminal, live: roots, context: fresh)
        #expect(throws: (any Error).self) {
            try SharedMediaNativeTerminalScan.requireAbsent([first.plan.queueID], container: h.container, inventoryID: h.inventoryID)
        }
        let late = try clone(first), conflicting = try clone(first, preserveID: first.plan.queueID)
        try SharedMediaNativeTerminalIdentity.requireCompatible(first, other: late)
        #expect(throws: (any Error).self) { try SharedMediaNativeTerminalIdentity.requireCompatible(first, other: conflicting) }
        try await rejectBatchBoundaryFailures(h, selected: selected, following: #require(following), live: roots)
        // Reopening runs the normal exhaustive scoped audit across the page
        // boundary, including both historical terminals and the live slot.
        phase("phase 8: cold scoped audit")
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let url = try #require(h.container.configurations.first).url
        let reopened = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
        #expect(reopened !== h.container)
        phase("cold container constructed")
        let cold = try await SharedMediaNativeOriginalOwner.appDispatch(
            account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        phase("cold dispatch constructed")
        var traceReports = 0
        let trace = SharedMediaNativeDebugHooks.InspectionTrace { value in
            traceReports += 1
            print("Terminal audit phase \(value.phase.rawValue); completed \(value.completed); elapsed \(value.elapsed); checkpoints \(value.checkpointCount); checkpoint time \(value.checkpointTime); saturated \(value.saturated)")
        }
        _ = try await cold.openApp(container: reopened, parent: h.parent, inventoryID: h.inventoryID, inspectionTrace: trace)
        #expect(traceReports > 0 && traceReports <= 64)
        #expect(!cold.hasInspectionTraceForTesting)
        phase("cold open completed")
        #expect(await cold.invalidateAndAwaitForAccountTransition())
        phase("phase 9: complete")
    }

    private func rejectBatchBoundaryFailures(_ h: SharedMediaNativeReceivingTerminalOwnerTests.Store,
                                            selected: [SharedMediaNativeReceivingTerminal.Snapshot],
                                            following: SharedMediaNativeReceivingTerminal.Snapshot,
                                            live: [UUID: SharedMediaNativeReceivingCleanGraph.Witness]) async throws {
        let last = try #require(selected.last)
        #expect(selected.count == SharedMediaStoragePolicy.pageSize)
        var checks = 0
        let matched = try SharedMediaNativeTerminalIdentity.comparePage(selected, other: last) { checks += 1 }
        #expect(matched == last.row.id && checks == 2) // Constant authority reads for a full batch.
        let cancelled = Task { @MainActor in
            var checks = 0
            do {
                _ = try SharedMediaNativeTerminalIdentity.comparePage(selected, other: last) {
                    checks += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                return false
            } catch is CancellationError { return checks == 1 }
            catch { return false }
        }
        #expect(await cancelled.value)

        let context = h.context(), inventory = try ownerTests.inventory(h, context)
        let revision = inventory.revision
        checks = 0
        #expect(throws: SharedMediaStorageFailure.self) {
            _ = try SharedMediaNativeTerminalIdentity.comparePage(selected, other: last) {
                checks += 1
                if checks == 2 { inventory.revision += 1; try context.save() }
                guard try ownerTests.inventory(h, h.context()).revision == revision else { throw SharedMediaStorageFailure.stale }
            }
        }
        #expect(checks == 2)
        inventory.revision = revision; try context.save()

        // Corrupt the first terminal beyond the page boundary. Its new queue ID
        // collides only with the final selected value, not an earlier comparison.
        let lateRow = try #require(try SharedMediaNativeReceivingPhaseGraph.row(following.row.id, in: context))
        let text = String(decoding: try following.value.encoded(), as: UTF8.self)
            .replacingOccurrences(of: following.value.plan.queueID.uuidString, with: last.value.plan.queueID.uuidString)
        let raw = try JSONDecoder().decode(Values.Released.self, from: Data(text.utf8))
        let collision = try Values.Released(plan: raw.plan, inventoryRevision: raw.inventoryRevision, outcomes: raw.outcomes)
        try restore(lateRow, collision); try context.save()
        let other = try SharedMediaNativeReceivingTerminal.read(lateRow, context: context, inventory: inventory)
        _ = try SharedMediaNativeTerminalIdentity.comparePage(Array(selected.dropLast()), other: other, checkpoint: {})
        #expect(throws: (any Error).self) { _ = try SharedMediaNativeTerminalIdentity.comparePage(selected, other: other, checkpoint: {}) }
        #expect(throws: (any Error).self) { try SharedMediaNativeTerminalIdentity.auditPage(selected, live: live, context: h.context()) }
        try restore(lateRow, following.value); try context.save()
        lateRow.resultData = Data(); try context.save()
        #expect(throws: (any Error).self) { try SharedMediaNativeTerminalIdentity.auditPage(selected, live: live, context: h.context()) }
        try restore(lateRow, following.value); try context.save()

        let first = try #require(selected.first)
        let old = try #require(try SharedMediaNativeReceivingPhaseGraph.row(first.row.id, in: context))
        context.delete(old); try context.save()
        #expect(throws: (any Error).self) { try SharedMediaNativeTerminalIdentity.auditPage([first], live: live, context: h.context()) }
        let p = first.value.plan
        let replacement = SharedMediaReceivingIntentRecord(packageID: p.package.id, inventoryID: p.profile.inventoryID,
            inventoryGeneration: p.profile.generation, ownerID: p.profile.ownerID, draftGeneration: p.package.generation,
            operationID: p.operationID, preparedData: Data(), preparedSHA256: p.preparedSHA256)
        try restore(replacement, first.value); context.insert(replacement); try context.save()
        #expect(replacement.persistentModelID != first.persistentID)
        #expect(throws: (any Error).self) { try SharedMediaNativeTerminalIdentity.auditPage([first], live: live, context: h.context()) }
    }

    @Test func terminalBytesUseExistingDurableCapAndCheckedRunway() throws {
        var totals = SharedMediaStoragePolicy.Totals()
        try totals.includePhotoPhysical(materialized: PhotoPreparationPolicy.durable - 1, reserved: 0)
        try totals.includePhotoPhysical(materialized: 1, reserved: 0)
        #expect(throws: (any Error).self) { try totals.includePhotoPhysical(materialized: 1, reserved: 0) }
        var summary = SharedMediaNativeTerminalScan.Summary()
        for _ in 0..<5 { try summary.include(1) }
        #expect(summary.bytes == 5 && summary.consumptionAdvances == 5)
        try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: Int64.max - 5,
            witnesses: [], terminalConsumptionAdvances: summary.consumptionAdvances)
        #expect(throws: (any Error).self) {
            try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: Int64.max - 4,
                witnesses: [], terminalConsumptionAdvances: summary.consumptionAdvances)
        }
        summary.bytes = Int64.max
        #expect(throws: (any Error).self) { try summary.include(1) }
        summary = .init(bytes: 0, consumptionAdvances: Int64.max)
        #expect(throws: (any Error).self) { try summary.include(1) }
    }

    @Test(arguments: [false, true])
    func historicalSharedOriginalAllowsRecipientRetirementAndRecovery(_ held: Bool) async throws {
        let (h, owner, before) = try await SharedMediaNativeOriginalDispositionSharingTests().fixture(foreign: false)
        let removed = try await owner.disposeAppReleaseOriginal(before)
        let historical = try await owner.finishAppRelease(removed)
        let assetID = before.plan.targets[0].original.assetID
        let c = h.context()
        let ref = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }))
        let package = try h.package(ref.packageID, in: c)
        let source = PhotoOriginalReference(ownerID: ref.ownerID, packageID: ref.packageID, referenceID: ref.id,
            assetID: assetID, assetGeneration: before.plan.targets[0].original.assetGeneration,
            draftGeneration: package.draftGeneration, referenceRevision: ref.revision)
        var heldRetiring: Values.Progress?
        if held {
            let ready = try await owner.prepareAndDeliverAppPhoto(original: source,
                recipe: SharedMediaNativeOriginalDispositionSharingTests.recipe)
            let prepared = try await owner.stageAppReceiving(packageID: source.packageID,
                draftGeneration: source.draftGeneration, pairIDs: [ready.intent().pairID])
            #expect(try ownerTests.terminal(h).value == historical)
            _ = try await owner.receiveAppPrepared(prepared)
            let admission = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
            _ = try await owner.stageAppRelease(admission)
            let started = try await owner.startAppRelease(admission.request)
            let pairRetiring = try await owner.retireAppReleasePair(started)
            let pairGone = try await owner.removeAppReleasePair(pairRetiring)
            heldRetiring = try await owner.disposeAppReleaseOriginal(pairGone)
            #expect(heldRetiring?.targets[0].stage == .originalRetiring)
        } else {
            let removal = try await owner.prepareAppOriginalRemoval(source)
            try await owner.removeAppOriginal(removal)
        }
        #expect(try ownerTests.terminal(h).value == historical)
        let liability = try SharedMediaNativeOriginalLiability.read(context: h.context(), inventoryID: h.inventoryID)
        let entry = try #require(liability.entries[assetID])
        #expect(entry.retiring && entry.acquisitionID == before.plan.targets[0].acquisitionID)
        #expect(entry.currentBytes > 0 && entry.currentBytes + entry.reservedBytes == 512)
        #expect(!liability.retainedTargets.contains(assetID))
        let fresh = h.context()
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: fresh,
            inventory: ownerTests.inventory(h, fresh), ownerID: h.ownerID, format: .appV2)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        try rejectRetirementCorruption(h, source: source, historical: historical)
        // The normal cold open runs ScopedAudit before either existing cleanup
        // owner may acquire an unlink witness. Historical reading grants none.
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        if let heldRetiring {
            let gone = try await cold.removeAppReleaseOriginal(heldRetiring)
            _ = try await cold.finishAppRelease(gone)
            #expect(try SharedMediaNativeTerminalScan.read(container: h.container,
                inventoryID: h.inventoryID).consumptionAdvances == 2)
        } else {
            try await cold.recoverAppOriginalRetirements()
        }
        #expect(try ownerTests.terminal(h).value == historical)
        let after = h.context()
        try SharedMediaNativeReceivingReleaseLiveAudit.absentOriginal(before.plan.targets[0],
            profile: before.plan.profile, inventory: ownerTests.inventory(h, after), context: after)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
        let reopened = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try ownerTests.terminal(h).value == historical)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    private func rejectRetirementCorruption(_ h: SharedMediaNativeAppMetadataTests.Store,
                                            source: PhotoOriginalReference, historical: Values.Released) throws {
        let c = h.context(), id = source.assetID, refID = source.referenceID, packageID = source.packageID
        let rows = try SharedMediaNativeAppOriginalRows(c, profile: historical.plan.profile, source: source)
        let ref = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == refID }))
        let edge = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == refID }))
        let mutations: [() -> Void] = [
            { rows.count.liveCount = 1 }, { rows.count.retirementID = UUID() },
            { ref.packageID = UUID() }, { ref.isLive = true }, { edge.stateRaw = "live" },
            { rows.member.membersData = Data() }, { rows.package.accountingTierRaw = "retained" },
            { rows.receipt.resultData = Data() }
        ]
        for mutate in mutations {
            // Persist one malformed join, read through a fresh context, then
            // restore the exact canonical values before the next mutation.
            let oldCount = rows.count.liveCount, oldRetirement = rows.count.retirementID
            let oldPackage = ref.packageID, oldLive = ref.isLive, oldEdge = edge.stateRaw
            let oldMembers = rows.member.membersData, oldTier = rows.package.accountingTierRaw
            let oldResult = rows.receipt.resultData
            mutate(); try c.save()
            #expect(throws: (any Error).self) { _ = try ownerTests.terminal(h) }
            rows.count.liveCount = oldCount; rows.count.retirementID = oldRetirement
            ref.packageID = oldPackage; ref.isLive = oldLive; edge.stateRaw = oldEdge
            rows.member.membersData = oldMembers; rows.package.accountingTierRaw = oldTier
            rows.receipt.resultData = oldResult; try c.save()
            #expect(try ownerTests.terminal(h).value == historical)
        }
        #expect(ref.packageID == packageID && rows.asset.id == id)
    }

    private func restore(_ row: SharedMediaReceivingIntentRecord, _ value: Values.Released) throws {
        let p = value.plan
        row.schemaVersion = 2; row.inventoryID = p.profile.inventoryID; row.inventoryGeneration = p.profile.generation
        row.ownerID = p.profile.ownerID; row.draftGeneration = p.package.generation; row.operationID = p.operationID
        row.phaseRaw = "released"; row.revision = try SharedMediaNativeReceivingTerminal.revision(value)
        row.preparedData = nil; row.preparedSHA256 = p.preparedSHA256; row.resultData = try value.encoded()
        row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(row.resultData!)
        row.releaseStartData = nil; row.releaseStartSHA256 = nil
        row.allocationData = nil; row.allocationSHA256 = nil
    }
    private func clone(_ source: Values.Released, preserveID: UUID? = nil) throws -> Values.Released {
        let ids = SharedMediaNativeTerminalIdentity.exclusive(source).subtracting(preserveID.map { [$0] } ?? [])
        var text = String(decoding: try source.encoded(), as: UTF8.self)
        for id in ids { text = text.replacingOccurrences(of: id.uuidString, with: UUID().uuidString) }
        let raw = try JSONDecoder().decode(Values.Released.self, from: Data(text.utf8))
        // Plan hash changes after remapping; all original association IDs stay.
        return try .init(plan: raw.plan, inventoryRevision: source.inventoryRevision, outcomes: raw.outcomes)
    }
}
