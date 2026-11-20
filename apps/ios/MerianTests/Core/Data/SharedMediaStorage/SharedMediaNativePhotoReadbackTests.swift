import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native mutable prepared-photo readback", .serialized)
@MainActor
struct SharedMediaNativePhotoReadbackTests {
    @Test(arguments: [1, 2])
    func exactOrderedBytesPreserveAllMetadataWithoutSave(_ count: Int) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count)
        let ids = try SharedMediaNativeReceivingStagingTests().pairIDs(request)
        let before = try SharedMediaNativeAppMetadataFacts.capture(h.context(), profile: request.profile)
        try owner.setMetadataFault { _ in Issue.record("Readback attempted metadata mutation") }
        try owner.setPreparationFault { if $0 != .beforeReadback && $0 != .afterPhotoReadbackSeal { Issue.record("Readback attempted preparation mutation") } }
        let metadata = try await owner.currentAppMetadata(packageID: h.packageID, draftGeneration: h.draft)
        let result = try await owner.readPreparedAppPhotos(expectedMetadata: metadata, pairIDs: ids)
        #expect(result.metadata.envelope == metadata.package.envelope)
        #expect(result.photos.count == count)
        #expect(try result.photos.map { try $0.pair.intent().pairID } == ids)
        for photo in result.photos {
            let intent = try photo.pair.intent()
            #expect(photo.original == intent.preparation.original.reference)
            #expect(Int64(photo.ai.count) == intent.ai.byteCount && SharedMediaAcquisitionEncoding.digest(photo.ai) == intent.ai.sha256)
            #expect(Int64(photo.display.count) == intent.display.byteCount && SharedMediaAcquisitionEncoding.digest(photo.display) == intent.display.sha256)
        }
        #expect(try SharedMediaNativeAppMetadataFacts.capture(h.context(), profile: request.profile) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["duplicate", "reversed", "omitted", "foreign", "empty", "text"])
    func selectionMismatchCannotReturnPartialProjection(_ fault: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: 2)
        var ids = try SharedMediaNativeReceivingStagingTests().pairIDs(request)
        let metadata = try await owner.currentAppMetadata(packageID: h.packageID, draftGeneration: h.draft)
        switch fault {
        case "duplicate": ids[1] = ids[0]
        case "reversed": ids.reverse()
        case "omitted": ids.removeLast()
        case "foreign": ids[1] = UUID()
        case "empty": ids = []
        default:
            let edit = try await owner.prepareAppMetadata(packageID: h.packageID, draftGeneration: h.draft, contexts: [.init(freeText: "Later exact text")])
            _ = try await owner.saveAppMetadata(edit)
        }
        let before = try h.package().supportingContextData
        await #expect(throws: (any Error).self) { _ = try await owner.readPreparedAppPhotos(expectedMetadata: metadata, pairIDs: ids) }
        #expect(try h.package().supportingContextData == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func preparedAndReceivedSlotsCannotUseMutableReadback(_ received: Bool) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try SharedMediaNativeReceivingStagingTests().pairIDs(request)
        let metadata = try await owner.currentAppMetadata(packageID: h.packageID, draftGeneration: h.draft)
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft, pairIDs: ids)
        if received { _ = try await owner.receiveAppPrepared(prepared) }
        let before = try SharedMediaNativeAppMetadataFacts.capture(h.context(), profile: request.profile)
        await #expect(throws: (any Error).self) { _ = try await owner.currentAppMetadata(packageID: h.packageID, draftGeneration: h.draft) }
        await #expect(throws: (any Error).self) { _ = try await owner.readPreparedAppPhotos(expectedMetadata: metadata, pairIDs: ids) }
        #expect(try SharedMediaNativeAppMetadataFacts.capture(h.context(), profile: request.profile) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["missing", "tampered", "replacement", "earlierReplacement", "metadata", "cancel", "account"])
    func finalReadSealRejectsRacesAndRevocation(_ fault: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: 2)
        let ids = try SharedMediaNativeReceivingStagingTests().pairIDs(request)
        let metadata = try await owner.currentAppMetadata(packageID: h.packageID, draftGeneration: h.draft)
        let intent = try SharedMediaNativeDerivativeIntent.decode(try #require(SharedMediaNativeDraftEnvelope.decode(metadata.envelope).intents.first).bytes)
        let file = h.parent.appendingPathComponent("photo/PhotoPreparation")
            .appendingPathComponent(h.ownerID.uuidString.lowercased()).appendingPathComponent(h.packageID.uuidString.lowercased())
            .appendingPathComponent(intent.ai.assetID.uuidString.lowercased())
        let gate = Gate(after: fault == "earlierReplacement" ? 4 : 1)
        try await owner.setAcquisitionEntryPause { if $0 == .readPair { await gate.pause() } }
        let operation = Task { try await owner.readPreparedAppPhotos(expectedMetadata: metadata, pairIDs: ids) }
        await gate.entered.wait()
        var transition: Task<Bool, Never>?
        switch fault {
        case "missing": try FileManager.default.removeItem(at: file)
        case "tampered": try Data([0]).write(to: file)
        case "replacement", "earlierReplacement":
            let bytes = try Data(contentsOf: file)
            // Retain the old inode to ensure replacement cannot reuse it.
            try FileManager.default.moveItem(at: file, to: file.appendingPathExtension("retained-test-original"))
            try bytes.write(to: file)
        case "metadata":
            let c = h.context(); try h.package(in: c).revision += 1; try c.save()
        case "cancel": operation.cancel()
        default:
            transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
        }
        await gate.release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        if let transition { #expect(await transition.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    @Test(arguments: ["package", "inventory", "member"])
    func logicalChangeAfterPhysicalSealCannotReturn(_ target: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture()
        let ids = try SharedMediaNativeReceivingStagingTests().pairIDs(request)
        let metadata = try await owner.currentAppMetadata(packageID: h.packageID, draftGeneration: h.draft)
        var reached = false
        try owner.setPreparationFault { point in
            guard point == .afterPhotoReadbackSeal else { return }; reached = true
            let c = h.context()
            switch target {
            case "package": try h.package(in: c).revision += 1
            case "inventory": try #require(try c.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1
            default: try #require(try c.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1
            }
            try c.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.readPreparedAppPhotos(expectedMetadata: metadata, pairIDs: ids) }
        #expect(reached)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private actor Gate {
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        var remaining: Int
        init(after: Int) { remaining = after }
        func pause() async {
            remaining -= 1
            if remaining == 0 { await entered.open(); await release.wait() }
        }
    }
}
