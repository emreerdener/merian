import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@Suite("Initial Capture prepared output recovery", .serialized)
@MainActor
struct CaptureInitialPreparedRecoveryTests {
    @Test(arguments: [false, true])
    func coldHandoffNeverNeedsToRerenderAFrozenSubmission(_ partial: Bool) async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let bytes = try image()
        let recipe = SharedMediaNativePreparationRecipe(format: .selectedStillImage, isPro: false,
            cropDisplaySize: 100, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0,
            sourceSelection: .init(x: 0.2, y: 0.2, width: 0.6, height: 0.6, source: .userSelection))
        var items: [CaptureInitialEvidencePreparation.Item] = []
        for _ in 0..<2 {
            let source = try await session.retain(itemID: UUID(), bytes: bytes, role: .sourceImage,
                contentType: "image/jpeg", context: .init(origin: .imported, cameraVerticalCenter: nil), review: .photo(recipe))
            items.append(.photo(source, recipe))
        }
        items.append(.description("Synthetic preparation recovery note"))
        let plan = try await session.prepare(items: items), input = try SharedMediaCaptureSubmissionContextTests.context(plan)
        if partial {
            try owner.configureCaptureArtifactWritingForTesting { point in
                if point == .afterReadySave { throw SharedMediaStorageFailure.unavailable }
            }
        } else {
            try owner.configureCaptureSubmissionWritingForTesting { point in
                if point == .beforeSave { throw SharedMediaStorageFailure.unavailable }
            }
        }
        await #expect(throws: (any Error).self) { _ = try await session.accept(context: input) }
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let saved = try #require(try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID,
            generation: plan.generation, context: read))
        #expect(saved.value.phase == .preparing)
        #expect(try read.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        let preparedRows = try store.rows().filter { $0.roleRaw == "prepared_image" }
        #expect(preparedRows.count == (partial ? 1 : 2))
        #expect(preparedRows.allSatisfy { $0.phaseRaw == "ready" })
        let retainedIDs = preparedRows.map(\.id)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        var cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        var reopened = try await CaptureInitialDraftSession.reopen(saved, requireCurrent: {}, resolveOwner: { cold })
        #expect(reopened.frozenPlan == plan)
        if partial {
            await #expect(throws: (any Error).self) { _ = try await reopened.accept(context: input) }
            let after = ModelContext(store.container); after.autosaveEnabled = false
            #expect(try after.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0)
            #expect(try after.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        } else {
            let accepted = try await reopened.accept(context: input)
            #expect(try await reopened.accept(context: input) == accepted)
            let after = ModelContext(store.container); after.autosaveEnabled = false
            #expect(try after.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        }
        let afterIDs = try store.rows().filter { $0.roleRaw == "prepared_image" }.map(\.id)
        #expect(Set(afterIDs) == Set(retainedIDs))
        if partial {
            for boundary in SharedMediaCaptureSourceDiscardBoundary.allCases {
                try cold.configureCaptureSourceDiscardForTesting { point in
                    if point == boundary { throw SharedMediaStorageFailure.unavailable }
                }
                await #expect(throws: (any Error).self) { try await reopened.abortPreparation() }
                let read = ModelContext(store.container); read.autosaveEnabled = false
                let held = try #require(try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID,
                    generation: plan.generation, context: read))
                #expect(held.value.phase == .abortingPreparation)
                #expect(held.value.items == saved.value.items && held.value.sources == saved.value.sources)
                #expect(try read.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0)
                #expect(await cold.invalidateAndAwaitForAccountTransition())
                cold = try await store.open()
                try await cold.resumeAppCaptureRoot()
                reopened = try await CaptureInitialDraftSession.reopen(held, requireCurrent: {}, resolveOwner: { cold })
                await #expect(throws: (any Error).self) { _ = try await reopened.accept(context: input) }
                await #expect(throws: (any Error).self) { _ = try await reopened.prepare(items: items) }
                let source = try #require(reopened.sources.first)
                await #expect(throws: (any Error).self) { _ = try await reopened.read(source.input) }
            }
            try await reopened.abortPreparation()
            #expect(reopened.journal?.value.phase == .editing)
            #expect(reopened.journal?.value.items == saved.value.items)
            #expect(reopened.frozenPlan == nil)
            let retired = try store.rows().filter { $0.roleRaw == "prepared_image" }
            #expect(retired.allSatisfy { $0.phaseRaw == "released" })
            for row in retired {
                let artifact = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
                #expect(artifact.retirement?.version == 2)
                #expect(artifact.retirement?.releasedRevision != nil)
            }
            for source in reopened.sources { #expect(try await reopened.read(source.input) == bytes) }
            let next = try await reopened.prepare(items: items)
            #expect(next.scanID == plan.scanID && next.generation == plan.generation)
            #expect(Set(next.uploads.filter { $0.role == .preparedImage }.map(\.artifact.mediaID))
                .isDisjoint(with: Set(plan.uploads.filter { $0.role == .preparedImage }.map(\.artifact.mediaID))))
            let nextContext = try SharedMediaCaptureSubmissionContextTests.context(next)
            let accepted = try await reopened.accept(context: nextContext)
            #expect(try await reopened.accept(context: nextContext) == accepted)
            let after = ModelContext(store.container); after.autosaveEnabled = false
            #expect(try after.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func ambiguousPartialHasOnlyAnAbortRecoveryRouteAndFinalCommitReplays() async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let recipe = SharedMediaNativePreparationRecipe(format: .selectedStillImage, isPro: false,
            cropDisplaySize: 100, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0,
            sourceSelection: .init(x: 0.2, y: 0.2, width: 0.6, height: 0.6, source: .userSelection))
        let source = try await session.retain(itemID: UUID(), bytes: image(), role: .sourceImage,
            contentType: "image/jpeg", context: .init(origin: .imported, cameraVerticalCenter: nil), review: .photo(recipe))
        let plan = try await session.prepare(items: [.photo(source, recipe)])
        try owner.configureCaptureArtifactWritingForTesting { point in
            if point == .afterPartialCreation { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await session.accept(context: SharedMediaCaptureSubmissionContextTests.context(plan))
        }
        let pendingRead = ModelContext(store.container); pendingRead.autosaveEnabled = false
        let pending = try #require(try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID,
            generation: plan.generation, context: pendingRead))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        await #expect(throws: (any Error).self) { _ = try await cold.captureDraftJournalPage() }
        await #expect(throws: (any Error).self) { _ = try await cold.readAppCaptureSource(source) }
        let handles = try await cold.capturePreparationAbortRecovery()
        let handle = try #require(handles.first)
        #expect(handles.count == 1 && handle.scanID == plan.scanID && handle.generation == plan.generation)
        let recovered = try await CaptureInitialDraftSession.reopen(pending, requireCurrent: {}, resolveOwner: { cold })
        #expect(recovered.needsPreparationAbort && recovered.sources.isEmpty)
        await #expect(throws: (any Error).self) { try recovered.freeze(plan) }
        var saves = 0
        try cold.configureCaptureDraftJournalForTesting { point in
            if point == .afterSave { saves += 1 }
            if saves == 2 && (point == .afterSave || point == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await recovered.abortPreparation() }
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let committed = try #require(try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID,
            generation: plan.generation, context: read))
        #expect(committed.value.phase == .editing)
        #expect(committed.value.abortedPreparations?.count == 1)
        try cold.configureCaptureDraftJournalForTesting(nil)
        try await recovered.abortPreparation()
        #expect(!recovered.needsPreparationAbort && recovered.journal == committed)
        #expect(recovered.sources.map(\.input) == [source])
        #expect(try await cold.abortAppCapturePreparation(handle) == committed)
        #expect(try await cold.readAppCaptureSource(source) == image())
        #expect(try read.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        var forged = committed.value
        let proof = try #require(forged.abortedPreparations?.first)
        let member = try #require(proof.members.first)
        forged.abortedPreparations = [.init(attemptSHA256: proof.attemptSHA256, planSHA256: proof.planSHA256,
            members: [.init(artifactID: member.artifactID, mediaID: member.mediaID, requestSHA256: String(repeating: "f", count: 64))])]
        let mutation = ModelContext(store.container); mutation.autosaveEnabled = false
        let row = try #require(try mutation.fetch(FetchDescriptor<SharedMediaCaptureDraftJournalRecord>()).first)
        row.bodyData = try forged.encoded(); row.bodySHA256 = SharedMediaAcquisitionEncoding.digest(row.bodyData)
        try mutation.save()
        await #expect(throws: (any Error).self) { _ = try await cold.captureDraftJournalPage() }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    private func image() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try #require(UIGraphicsImageRenderer(size: .init(width: 80, height: 80), format: format).image { context in
            UIColor.green.setFill(); context.fill(.init(x: 0, y: 0, width: 80, height: 80))
        }.jpegData(compressionQuality: 0.9))
    }
}
