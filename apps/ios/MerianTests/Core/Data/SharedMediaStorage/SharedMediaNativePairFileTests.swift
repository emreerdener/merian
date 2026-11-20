import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native paired files", .serialized)
@MainActor
struct SharedMediaNativePairFileTests {
    private typealias Harness = SharedMediaNativePreparationTests.Harness
    private enum Fault: Error { case injected }
    private static let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false,
        cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)

    @Test func readyPairReopensAndRetiresBothOutputsWithoutTouchingOriginal() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        #expect(ready.phase == "ready" && ready.work.allSatisfy { $0.phase == "completed" && $0.closure == nil })
        #expect(!(try await owner.snapshot().requiresRecovery))
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        for work in ready.work { #expect(FileManager.default.fileExists(atPath: try file(h, state: ready, workID: work.id).path)) }
        await #expect(throws: (any Error).self) { try await owner.abandonPlannedPreparation(ready.plan) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.preparedFileState(packageID: h.packageID) == ready)
        #expect(try await cold.recoverPreparedFiles(packageID: h.packageID) == ready)
        try await cold.retirePreparedFiles(ready)
        try requireOriginalOnly(h, original)
        #expect(!(try await cold.snapshot().requiresRecovery))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["sharedLease", "preparationLease", "nonNative"])
    func leaseFreeMembershipRequiresCompleteNativeReadyAuthority(_ corruption: String) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let context = ModelContext(h.container); context.autosaveEnabled = false
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        let pair = try #require(context.fetch(FetchDescriptor<SharedMediaDerivativePairRecord>()).first)
        let input = try ready.intent().ai, file = try ready.file(input.id)
        let clean = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        let membership = try clean.membership(packageID: h.packageID)
        #expect(membership.ids(.allocation).contains(input.assetID))
        #expect(membership.ids(.reference).contains(input.referenceID))
        #expect(!membership.ids(.lease).contains(input.leaseID))
        if corruption == "sharedLease" {
            context.insert(SharedMediaLeaseRecord(id: input.leaseID, allocationID: input.assetID,
                processEpoch: ready.plan.writerEpoch, purposeRaw: SharedMediaNativePairPlanGraph.contract, stateRaw: "closed"))
        } else if corruption == "preparationLease" {
            context.insert(PhotoPreparationLease(id: input.leaseID, packageID: h.packageID, assetID: input.assetID,
                ownerID: pair.ownerID, processEpoch: ready.plan.writerEpoch, purposeRaw: SharedMediaNativePairPlanGraph.contract,
                partialFileToken: file.token + ".partial", finalFileToken: file.token, reservedByteCount: 0,
                allocatedByteCount: input.byteCount, writerStateRaw: "closedPairWaiting", terminalProof: nil))
        } else { pair.contractVersion = "nonNative" }
        #expect(throws: SharedMediaStorageFailure.self) { try SharedMediaPendingGraph.derive(in: context, inventory: inventory) }
        context.rollback()
        try await owner.retirePreparedFiles(ready)
        try requireOriginalOnly(h, original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforeFileReserve, .beforeFileIdentity, .beforeFileCompletion, .beforeFilePublish])
    func failedSaveRetainsExactRecoveryOrRetirementState(_ point: SharedMediaNativePreparationBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        try owner.setPreparationFault { if $0 == point { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe) }
        try owner.setPreparationFault(nil)
        let saved = try await owner.preparedFileState(packageID: h.packageID)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.preparedFileState(packageID: h.packageID) == saved)
        if saved.phase == "planned" { try await cold.abandonPlannedPreparation(saved.plan) }
        else {
            let recovered = try await cold.recoverPreparedFiles(packageID: h.packageID)
            if point == .beforeFilePublish { #expect(recovered.phase == "ready") }
            try await cold.retirePreparedFiles(recovered)
        }
        try requireOriginalOnly(h, original)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.afterFileReserve, .afterFileIdentity, .afterFileCompletion, .afterFilePublish])
    func lostSaveAcknowledgementRecoversExactPostState(_ point: SharedMediaNativePreparationBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        try owner.setPreparationFault { if $0 == point { throw Fault.injected } }
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        #expect(ready.phase == "ready")
        try owner.setPreparationFault(nil)
        try await owner.retirePreparedFiles(ready)
        try requireOriginalOnly(h, original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterPartialCreate, .duringWrite, .afterRename])
    func interruptedFileWorkReopensWithoutPreparingAgain(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        try await owner.setPairFileFault { if $0 == point { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe) }
        try await owner.setPairFileFault(nil)
        let state = try await owner.preparedFileState(packageID: h.packageID)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        #expect(try await cold.preparedFileState(packageID: h.packageID) == state)
        let recovered = try await cold.recoverPreparedFiles(packageID: h.packageID)
        #expect(recovered.phase == "writing") // The second output was never created.
        try await cold.retirePreparedFiles(recovered)
        try requireOriginalOnly(h, original)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativePreparationBoundary.beforeFileRetire, .afterFileRetire, .beforeFileRelease, .afterFileRelease])
    func retirementSaveBoundariesPreserveDraftAndCapacity(_ point: SharedMediaNativePreparationBoundary) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        try owner.setPreparationFault { if $0 == point { throw Fault.injected } }
        if point == .beforeFileRetire || point == .beforeFileRelease {
            await #expect(throws: Fault.self) { try await owner.retirePreparedFiles(ready) }
            let state = try await owner.preparedFileState(packageID: h.packageID)
            #expect(state.phase == (point == .beforeFileRetire ? "ready" : "retiring"))
            #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
            try owner.setPreparationFault(nil)
            try await owner.retirePreparedFiles(state)
        } else { try await owner.retirePreparedFiles(ready) }
        try requireOriginalOnly(h, original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func firstUnlinkFailureRetainsBothLiabilitiesAndOneCanonicalClosure() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        try await owner.setPairFileFault { if $0 == .afterUnlink { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.retirePreparedFiles(ready) }
        try await owner.setPairFileFault(nil)
        let state = try await owner.preparedFileState(packageID: h.packageID), intent = try state.intent()
        #expect(state.phase == "retiring")
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
        let ai = try #require(state.work.first { $0.id == intent.ai.id }), display = try #require(state.work.first { $0.id == intent.display.id })
        let raw = try #require(ai.closure), closure = try SharedMediaNativePairClosure.decode(raw)
        #expect(display.closure == (try closure.siblingMarker()))
        #expect(raw.utf8.count + (display.closure?.utf8.count ?? 0) <= (try SharedMediaNativePairClosure.maximumEncodingBytes(ready)))
        #expect(Set(state.work.compactMap(\.retirementID)) == [closure.retirementID])
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await h.open()
        try await cold.retirePreparedFiles(state)
        try requireOriginalOnly(h, original)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func replacementAtRetiredNameCannotBeDeletedAsOldOutput() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        try owner.setPreparationFault { if $0 == .afterFileRetire { throw Fault.injected } }
        // A post-save error is recovered exactly, so stop the physical unlink
        // instead and retain the second output's original saved descriptor.
        try await owner.setPairFileFault { if $0 == .afterUnlink { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.retirePreparedFiles(ready) }
        let state = try await owner.preparedFileState(packageID: h.packageID)
        let second = try #require(state.work.last), path = try file(h, state: state, workID: second.id)
        let bytes = try Data(contentsOf: path)
        try bytes.write(to: path, options: .atomic)
        try owner.setPreparationFault(nil)
        await #expect(throws: (any Error).self) { try await owner.retirePreparedFiles(state) }
        #expect(FileManager.default.fileExists(atPath: path.path))
        #expect(try Data(contentsOf: path) == bytes)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["sibling", "membership", "prestate", "successor"])
    func alteredClosureCannotAuthorizeRecovery(_ field: String) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        try owner.setPreparationFault { if $0 == .beforeFileRelease { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.retirePreparedFiles(ready) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let context = ModelContext(h.container)
        let leases = try context.fetch(FetchDescriptor<PhotoPreparationLease>())
        if field == "sibling" {
            let sibling = try #require(leases.first { $0.terminalProof?.hasPrefix("nativePairClosureV1:") == true })
            sibling.terminalProof = "nativePairClosureV1:" + UUID().uuidString.lowercased() + ":" + String(repeating: "0", count: 64)
        } else if field == "membership" {
            let row = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
            row.revision += 1
        } else if field == "successor" {
            let member = try #require(context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first)
            let saved = try SharedMediaMembership.decode(member.membersData)
            let changed = try SharedMediaMembership(groups: saved.groups.map { group in
                guard group.kind == .edge else { return group }
                return .init(kind: group.kind, ids: (Array(group.ids.dropFirst()) + [UUID()]).sorted { $0.uuidString < $1.uuidString })
            })
            member.membersData = try changed.encoded() // Same revision and counts.
            let canonical = try #require(leases.first { $0.terminalProof?.hasPrefix("{") == true })
            let raw = try #require(canonical.terminalProof)
            var json = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            json["afterMembershipHash"] = SharedMediaNativePairClosure.digest(member.membersData)
            let closure = try JSONDecoder().decode(SharedMediaNativePairClosure.self, from: JSONSerialization.data(withJSONObject: json))
            canonical.terminalProof = try closure.encoded()
            let sibling = try #require(leases.first { $0.id != canonical.id }); sibling.terminalProof = try closure.siblingMarker()
            let pair = try #require(context.fetch(FetchDescriptor<SharedMediaDerivativePairRecord>()).first)
            let work = try #require(context.fetch(FetchDescriptor<SharedMediaDerivativeWorkRecord>()).first)
            let package = try #require(context.fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
            let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
            // Exercise the closure itself, independently of the broader graph
            // audit, which also rejects this otherwise well-formed swap.
            #expect(throws: (any Error).self) {
                try closure.require(work: work, pair: pair, package: package, inventory: inventory, context: context)
            }
        } else {
            let canonical = try #require(leases.first { $0.terminalProof?.hasPrefix("{") == true })
            let raw = try #require(canonical.terminalProof)
            var json = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
            json["beforeHash"] = String(repeating: "0", count: 64)
            canonical.terminalProof = String(data: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)
        }
        try context.save()
        #expect(throws: (any Error).self) { try SharedMediaNativeAcquisitionGraph.audit(context: ModelContext(h.container), inventoryID: h.inventoryID) }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
    }

    @Test(arguments: ["x", "\u{0001}"])
    func maximumSupportingContentStillReservesRetirementEncoding(_ character: String) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let edit = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: (0..<4).map { _ in ObservationContext(freeText: String(repeating: character, count: 8_000)) })
        _ = try await owner.saveMetadata(edit)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        #expect(try SharedMediaNativePairClosure.maximumStateBytes(ready) <= PhotoPreparationPolicy.metadata)
        try await owner.retirePreparedFiles(ready)
        let envelope = try SharedMediaNativeDraftEnvelope.decode(h.state().envelope)
        #expect(envelope.contexts.reduce(0) { $0 + $1.freeText.utf16.count } == 32_000)
        try requireOriginalOnly(h, original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func readyRetirementNeedsNoNewPreparationReservation() async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        let edit = try await owner.prepareMetadata(packageID: h.packageID, draftGeneration: h.draft,
            contexts: (0..<4).map { _ in ObservationContext(freeText: String(repeating: "\u{0001}", count: 8_000)) })
        _ = try await owner.saveMetadata(edit)
        let ready = try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe)
        let readyProjection = try SharedMediaNativePairClosure.maximumStateBytes(ready)
        let required = try SharedMediaStoragePolicy.add(SharedMediaStoragePolicy.reserve, readyProjection)
        #expect(throws: SharedMediaStorageFailure.self) { try budget(h).totals.checkAvailable(required - 1) }
        try budget(h).totals.checkAvailable(required)
        try owner.setPreparationFault { if $0 == .beforeFileRelease { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.retirePreparedFiles(ready) }
        let retiring = try await owner.preparedFileState(packageID: h.packageID)
        #expect(retiring.phase == "retiring")
        // Both liabilities still exist, but no writer or processor can resume.
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
        #expect(try SharedMediaNativePairClosure.maximumStateBytes(retiring) == readyProjection)
        #expect(throws: SharedMediaStorageFailure.self) { try budget(h).totals.checkAvailable(required - 1) }
        try budget(h).totals.checkAvailable(required)
        try owner.setPreparationFault(nil)
        try await owner.retirePreparedFiles(retiring)
        try requireOriginalOnly(h, original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [0, 1])
    func retiringUnfinishedOutputsRetainExactReservation(_ completed: Int) async throws {
        let h = try Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        var identities = 0
        try owner.setPreparationFault {
            if $0 == .beforeFileIdentity {
                identities += 1
                if identities == completed + 1 { throw Fault.injected }
            }
        }
        await #expect(throws: Fault.self) { try await owner.qualifyPreparedFiles(original: original, recipe: Self.recipe) }
        let writing = try await owner.preparedFileState(packageID: h.packageID)
        #expect(writing.work.filter { $0.finalIdentity != nil }.count == completed)
        try owner.setPreparationFault { if $0 == .beforeFileRelease { throw Fault.injected } }
        await #expect(throws: Fault.self) { try await owner.retirePreparedFiles(writing) }
        let retiring = try await owner.preparedFileState(packageID: h.packageID)
        let unfinished = try retiring.work.filter { $0.finalIdentity == nil }.reduce(Int64(0)) { sum, work in
            try SharedMediaStoragePolicy.add(sum, retiring.selected(work.id).1.byteCount)
        }
        #expect(unfinished > 0)
        let totals = try budget(h).totals
        let required = try PhotoPreparationPolicy.add([SharedMediaStoragePolicy.reserve,
            SharedMediaNativePairClosure.maximumStateBytes(retiring), unfinished])
        #expect(throws: SharedMediaStorageFailure.self) { try totals.checkAvailable(required - 1) }
        try totals.checkAvailable(required)
        try owner.setPreparationFault(nil)
        try await owner.retirePreparedFiles(retiring)
        try requireOriginalOnly(h, original)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func budget(_ h: Harness) throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
        let context = ModelContext(h.container)
        let inventory = try #require(context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first)
        return try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
    }

    private func file(_ h: Harness, state: SharedMediaNativePairFileState, workID: UUID) throws -> URL {
        try h.base.appendingPathComponent("photo/PhotoPreparation/" + state.file(workID).token)
    }
    private func requireOriginalOnly(_ h: Harness, _ original: PhotoOriginalReference) throws {
        let context = ModelContext(h.container)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()) == 1)
        #expect(try Data(contentsOf: h.file(original)) == h.bytes)
    }
}
