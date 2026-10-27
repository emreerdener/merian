import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Frozen received-photo input readback", .serialized)
@MainActor
struct SharedMediaNativeReceivedPhotoReadbackTests {
    @Test(arguments: [1, 2])
    func exactFrozenInputDoesNotChangeHeldWork(_ count: Int) async throws {
        let (h, owner, prepared) = try await fixture(count: count)
        let before = try SharedMediaNativeReceivingStagingTests().facts(h)
        try owner.setMetadataFault { if $0 != .beforeReadback { Issue.record("Readback attempted a write") } }
        let value = try await owner.readReceivedAppPhotos(prepared)
        try check(value, prepared: prepared)
        #expect(try SharedMediaNativeReceivingStagingTests().facts(h) == before)
        let context = h.context()
        #expect(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).allSatisfy { $0.queueNeedsAttention && $0.queueAttemptCount == 0 })
        #expect(try context.fetch(FetchDescriptor<OfflineJobRecord>()).allSatisfy { $0.status == .needsAttention && $0.attemptCount == 0 })
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test
    func coldReopenReadsTheSameFrozenInput() async throws {
        let (h, owner, prepared) = try await fixture(count: 2)
        let first = try await owner.readReceivedAppPhotos(prepared)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let value = try await cold.readReceivedAppPhotos(prepared)
        try check(value, prepared: prepared)
        #expect(value.cohort == first.cohort && value.supportingBytes == first.supportingBytes)
        #expect(value.photos.map(\.ai) == first.photos.map(\.ai))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["prepared", "abandoned", "release"])
    func otherPhasesCannotReadReceivedInput(_ phase: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(request)
        if phase == "abandoned" { _ = try await owner.abandonAppReceiving(prepared) }
        if phase == "release" {
            _ = try await owner.receiveAppPrepared(prepared)
            let admission = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
            #expect(try await owner.stageAppRelease(admission) == .staged(admission.request))
            // The generic receiving snapshot deliberately rejects release sidecars.
            let release = SharedMediaNativeReleaseStartOwnerTests()
            let before = try release.staged(h), row = try release.row(h)
            let revision = try release.inventory(h, h.context()).revision
            await #expect(throws: (any Error).self) { _ = try await owner.readReceivedAppPhotos(prepared) }
            let after = try release.staged(h)
            #expect(after.origin.request == before.origin.request && after.origin.header == before.origin.header)
            #expect(after.components.progress == before.components.progress)
            #expect(after.funding.historical == before.funding.historical && after.funding.staged == before.funding.staged)
            #expect(after.funding.release.before == before.funding.release.before && after.funding.release.after == before.funding.release.after)
            #expect(try release.row(h) == row)
            #expect(try release.inventory(h, h.context()).revision == revision)
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            return
        }
        let before = try SharedMediaNativeReceivingStagingTests().facts(h)
        await #expect(throws: (any Error).self) { _ = try await owner.readReceivedAppPhotos(prepared) }
        #expect(try SharedMediaNativeReceivingStagingTests().facts(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["identity", "order", "supporting", "consumer", "queue"])
    func changedIdentityOrHeldRowsCannotSupplyInput(_ fault: String) async throws {
        let (h, owner, prepared) = try await fixture(count: 2)
        var candidate = prepared
        if ["identity", "order", "supporting"].contains(fault) {
            var json = try #require(try JSONSerialization.jsonObject(with: prepared.encoded()) as? [String: Any])
            if fault == "identity" { json["operationID"] = UUID().uuidString }
            else {
                // Alter exact canonical input without manufacturing another
                // receiving transaction or weakening the production codec.
                let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
                var cohort = try #require(try JSONSerialization.jsonObject(with: frozen.encoded()) as? [String: Any])
                if fault == "order" {
                    var entries = try #require(cohort["entries"] as? [[String: Any]])
                    entries.reverse()
                    for index in entries.indices { entries[index]["position"] = index }
                    cohort["entries"] = entries
                } else {
                    let supporting = SharedMediaNativeFrozenSupporting(contexts: [.init(freeText: "Changed after submission")], presentation: [])
                    cohort["supportingBytes"] = try supporting.encoded().base64EncodedString()
                }
                let bytes = try JSONSerialization.data(withJSONObject: cohort, options: [.sortedKeys, .withoutEscapingSlashes])
                let blob = SharedMediaNativePreparationBlob(bytes: bytes)
                json["cohort"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blob))
            }
            // A malformed descriptor is also an acceptable closed rejection.
            let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
            guard let altered = try? JSONDecoder().decode(SharedMediaNativeReceivingIntent.Prepared.self, from: bytes) else {
                Issue.record("Fixture must decode to reach the exact saved-identity comparison")
                _ = await owner.invalidateAndAwaitForAccountTransition(); return
            }
            candidate = altered
        } else {
            let context = h.context()
            if fault == "consumer" {
                try #require(try context.fetch(FetchDescriptor<SharedMediaConsumerRecord>()).first).revision += 1
            } else {
                try #require(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).queueAttemptCount += 1
            }
            try context.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.readReceivedAppPhotos(candidate) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["missing", "tampered", "replacement", "earlierReplacement", "cancel", "account", "package", "consumerDeleted", "queueDeleted"])
    func finalCohortSealRejectsFileAndAuthorityRaces(_ fault: String) async throws {
        let (h, owner, prepared) = try await fixture(count: 2)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let intent = try SharedMediaNativeDerivativeIntent.decode(try #require(frozen.entries.first).intent.bytes)
        let file = h.parent.appendingPathComponent("photo/PhotoPreparation")
            .appendingPathComponent(h.ownerID.uuidString.lowercased()).appendingPathComponent(h.packageID.uuidString.lowercased())
            .appendingPathComponent(intent.ai.assetID.uuidString.lowercased())
        let gate = Gate(after: fault == "earlierReplacement" || fault == "account" ? 2 : 1)
        try await owner.setAcquisitionEntryPause { if $0 == .readPair { await gate.pause() } }
        let operation = Task { try await owner.readReceivedAppPhotos(prepared) }
        await gate.entered.wait()
        var transition: Task<Bool, Never>?
        switch fault {
        case "missing": try FileManager.default.removeItem(at: file)
        case "tampered": try Data([0]).write(to: file)
        case "replacement", "earlierReplacement":
            let bytes = try Data(contentsOf: file)
            try FileManager.default.moveItem(at: file, to: file.appendingPathExtension("retained-test-original"))
            try bytes.write(to: file)
        case "cancel": operation.cancel()
        case "package":
            let context = h.context(); try h.package(in: context).revision += 1; try context.save()
        case "consumerDeleted":
            let context = h.context()
            context.delete(try #require(try context.fetch(FetchDescriptor<SharedMediaConsumerRecord>()).first))
            try context.save()
        case "queueDeleted":
            let context = h.context()
            context.delete(try #require(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).first))
            try context.save()
        default:
            transition = Task { await owner.invalidateAndAwaitForAccountTransition() }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
        }
        await gate.release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        if fault == "consumerDeleted" { #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0) }
        if fault == "queueDeleted" { #expect(try h.context().fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0) }
        if let transition { #expect(await transition.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }

    private func fixture(count: Int) async throws -> (SharedMediaNativeAppMetadataTests.Store, SharedMediaNativeOriginalOwner, SharedMediaNativeReceivingIntent.Prepared) {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count, staged: true)
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(request)
        _ = try await owner.receiveAppPrepared(prepared)
        return (store, owner, prepared)
    }
    private func check(_ value: SharedMediaNativeReceivedPhotoReadback, prepared: SharedMediaNativeReceivingIntent.Prepared) throws {
        #expect(try value.prepared.encoded() == prepared.encoded())
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let intents = try frozen.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes) }
        #expect(value.supportingBytes == frozen.supportingBytes)
        #expect(value.photos.count == intents.count)
        #expect(value.photos.map(\.pairID) == intents.map(\.pairID))
        for (photo, intent) in zip(value.photos, intents) {
            #expect(Int64(photo.ai.count) == intent.ai.byteCount)
            #expect(SharedMediaAcquisitionEncoding.digest(photo.ai) == intent.ai.sha256)
        }
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
