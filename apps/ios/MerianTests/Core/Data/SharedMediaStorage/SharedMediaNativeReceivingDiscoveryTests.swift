import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native received identity discovery", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativeReceivingDiscoveryTests {
    @Test func preparedStagedAndReleasingWorkIsNotAReceivedCandidate() async throws {
        let (h, owner, _) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let absentPackage = UUID()
        #expect(try await owner.discoverAppReceivingSlot(packageID: absentPackage) == nil)
        #expect(try await owner.discoverAppReceivingIntent(packageID: absentPackage) == nil)
        #expect(try await owner.discoverAppReceivedCandidates().isEmpty)
        let prepared = try #require(try await owner.discoverAppReceivingIntent(packageID: h.packageID))
        _ = try await owner.receiveAppPrepared(prepared)
        let candidates = try await owner.discoverAppReceivedCandidates()
        #expect(candidates.count == 1 && candidates.first?.operationID == prepared.operationID)
        let admission = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
        _ = try await owner.stageAppRelease(admission)
        #expect(try await owner.discoverAppReceivedCandidates().isEmpty)
        _ = try await owner.startAppRelease(admission.request)
        #expect(try await owner.discoverAppReceivedCandidates().isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["legacy", "roles", "bound"], [false, true])
    func allocationKeepsExactSelectedIdentityAcrossColdRecovery(projection: String, settled: Bool) async throws {
        let (h, owner, prepared) = try await SharedMediaNativePhotoAllocationTests().fixture()
        do {
            let candidates = try await owner.discoverAppReceivedCandidates()
            let selected = try #require(candidates.first)
            #expect(candidates.count == 1)
            let model = CaptureNativeRecoveryModel(ownerID: h.ownerID, isCurrent: { true }) {
                try await owner.discoverAppReceivedCandidates()
            }
            await model.open()
            #expect(model.state == .unselected(candidates))
            await model.select(selected)
            #expect(model.state == .holding(selected))
            let receipt = SharedMediaNativePhotoAllocation.Receipt(assignmentDigest: String(repeating: "a", count: 64),
                createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001)
            if projection == "legacy" {
                _ = try await owner.allocateAppPhoto(prepared, authorizeCreate: { _, validate in
                    try validate(); return .init(recipient: .gemini, validate: {})
                }) { _, validate, settle in
                    try validate(); try settle()
                    return settled ? .allocated(receipt) : .held(.notFound)
                }
            } else {
                _ = try await owner.allocateAppPhotoRoles(prepared, backendBinding: projection == "bound", authorizeCreate: { _, validate in
                    try validate(); return .init(recipient: .gemini, validate: {})
                }) { request, validate, settle in
                    try validate(); try settle()
                    guard settled else { return .held(.notFound) }
                    let entries = try SharedMediaNativePhotoRoleMapping.references(request.allocation.claim).enumerated().map { index, reference in
                        SharedMediaNativePhotoRoleMapping.Entry(photoOrdinal: index / 3,
                            role: SharedMediaNativePhotoRoleMapping.Role.allCases[index % 3], referenceID: reference, objectID: UUID())
                    }
                    return .allocated(.init(receipt: receipt, entries: entries,
                        backendBinding: projection == "bound" ? InitialPhotoUploadTicketTests().binding() : nil))
                }
            }
            let before = try NativePhotoStatusRecoveryTests().row(h)
            let saved = try NativePhotoStatusRecoveryTests().saved(h)
            #expect(saved.version == (projection == "legacy" ? 1 : projection == "roles" ? 2 : 6))
            #expect((saved.receipt != nil) == settled)
            try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Discovery saved allocation state") } }
            await model.refresh()
            #expect(model.state == .holding(selected))
            #expect(try await owner.discoverAppReceivedCandidates() == candidates)
            #expect(try NativePhotoStatusRecoveryTests().row(h) == before)
            model.close()
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
            do {
                try cold.setMetadataFault { if $0 == .beforeSave { Issue.record("Cold discovery saved state") } }
                let recovered = CaptureNativeRecoveryModel(ownerID: h.ownerID, isCurrent: { true }) {
                    try await cold.discoverAppReceivedCandidates()
                }
                await recovered.open()
                #expect(recovered.state == .unselected(candidates))
                await recovered.select(selected)
                #expect(recovered.state == .holding(selected))
                #expect(try NativePhotoStatusRecoveryTests().row(h) == before)
                recovered.close()
                #expect(await cold.invalidateAndAwaitForAccountTransition())
            } catch { _ = await cold.invalidateAndAwaitForAccountTransition(); throw error }
        } catch { _ = await owner.invalidateAndAwaitForAccountTransition(); throw error }
    }

    @Test func twoDurablePackagesRequireExplicitSelection() async throws {
        let (h, owner, _) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let first = try #require(try await owner.discoverAppReceivingIntent(packageID: h.packageID))
        _ = try await owner.receiveAppPrepared(first)
        let packageID = UUID(), draft = UUID()
        let request = try await owner.prepareAppOriginal(packageID: packageID, draftGeneration: draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        let acquired = try await owner.acquireAppOriginal(request) { bytes }
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: packageID,
            referenceID: request.referenceID, assetID: request.assetID, assetGeneration: request.assetGeneration,
            draftGeneration: draft, referenceRevision: acquired.referenceRevision)
        let ready = try await owner.prepareAndDeliverAppPhoto(original: original,
            recipe: .init(format: .stillImage, isPro: false, cropDisplaySize: nil,
                quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
        let second = try await owner.stageAppReceiving(packageID: packageID, draftGeneration: draft,
            pairIDs: [ready.intent().pairID], photoAdmission: .init(authorization: .init(recipient: .gemini, validate: {})))
        _ = try await owner.receiveAppPrepared(second)
        _ = try await owner.allocateAppPhoto(second, authorizeCreate: { _, validate in
            try validate(); return .init(recipient: .gemini, validate: {})
        }) { _, validate, settle in try validate(); try settle(); return .held(.notFound) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.closed } }
        let model = CaptureNativeRecoveryModel(ownerID: h.ownerID, isCurrent: { true }) {
            try await cold.discoverAppReceivedCandidates()
        }
        await model.open()
        guard case .unselected(let candidates) = model.state else {
            Issue.record("Multiple durable packages must remain unselected")
            _ = await cold.invalidateAndAwaitForAccountTransition(); return
        }
        #expect(Set(candidates.map(\.packageID)) == Set([h.packageID, packageID]))
        let selected = try #require(candidates.first { $0.packageID == packageID })
        await model.select(selected)
        #expect(model.state == .holding(selected))
        model.close()
        #expect(try await cold.discoverAppReceivedCandidates() == candidates)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["foreign", "orphan", "malformed", "allocation"])
    func rawCorruptionCannotDisappearBehindCandidateFiltering(_ fault: String) async throws {
        let (h, owner, _) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let prepared = try #require(try await owner.discoverAppReceivingIntent(packageID: h.packageID))
        _ = try await owner.receiveAppPrepared(prepared)
        let context = h.context()
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: context))
        let hash = row.preparedSHA256
        var orphan: SharedMediaReceivingIntentRecord?
        switch fault {
        case "foreign": row.ownerID = UUID()
        case "orphan":
            let extra = SharedMediaReceivingIntentRecord(packageID: UUID(), inventoryID: h.inventoryID,
                inventoryGeneration: prepared.profile.generation, ownerID: h.ownerID,
                draftGeneration: h.draft, operationID: UUID(), preparedData: try prepared.encoded(), preparedSHA256: hash)
            context.insert(extra); orphan = extra
        case "allocation": row.allocationData = Data(); row.allocationSHA256 = String(repeating: "a", count: 64)
        default: row.preparedSHA256 = String(repeating: "f", count: 64)
        }
        try context.save()
        await #expect(throws: (any Error).self) { _ = try await owner.discoverAppReceivedCandidates() }
        if let orphan { context.delete(orphan) }
        row.ownerID = h.ownerID; row.preparedSHA256 = hash
        row.allocationData = nil; row.allocationSHA256 = nil; try context.save()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["account", "deletion"])
    func auditSuspensionCannotReturnAnInvalidatedIdentity(_ change: String) async throws {
        let (h, first, _) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let prepared = try #require(try await first.discoverAppReceivingIntent(packageID: h.packageID))
        _ = try await first.receiveAppPrepared(prepared)
        #expect(await first.invalidateAndAwaitForAccountTransition())
        let base = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime)
        var current = true
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: h.ownerID,
            begin: base.begin, isCurrent: { current && base.isCurrent($0) }, finish: base.finish)
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: account, drain: .init())
        let gate = Gate()
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID,
            pause: { await gate.pause() })
        await gate.arm()
        let read = Task { try await owner.discoverAppReceivedCandidates() }
        await gate.entered.wait()
        if change == "account" { current = false }
        else {
            let context = h.context()
            let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: context))
            context.delete(row); try context.save()
        }
        await gate.release.open()
        await #expect(throws: (any Error).self) { _ = try await read.value }
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }

    private actor Gate {
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        private var armed = false
        func arm() { armed = true }
        func pause() async {
            guard armed else { return }
            await entered.open(); await release.wait()
        }
    }
}
