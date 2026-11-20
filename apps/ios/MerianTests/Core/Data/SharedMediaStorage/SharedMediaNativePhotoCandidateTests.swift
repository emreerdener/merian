import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Saved inactive CPM photo admission", .serialized)
@MainActor
struct SharedMediaNativePhotoCandidateTests {
    typealias Admission = SharedMediaNativePhotoAdmission
    typealias Candidate = SharedMediaNativePhotoCandidate
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    private func admission(_ recipient: IdentificationRecipientExpectation = .gemini) throws -> Admission {
        try .init(authorization: .init(recipient: recipient, validate: {}))
    }
    @Test func independentCandidateGoldenAndProcessorBinding() throws {
        func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))! }
        func role(_ value: Int) -> SharedMediaNativePhotoContent.Role {
            .init(referenceID: id(value), byteCount: 1, sha256: String(repeating: "a", count: 64), contentType: "image/jpeg")
        }
        let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: false, cropDisplaySize: nil,
            quarterTurns: 0, scale: 1, offsetX: -0.0, offsetY: 0)
        let content = try SharedMediaNativePhotoContent(scanID: id(1), packageID: id(2),
            photos: [.init(source: role(3), ai: role(4), display: role(5), recipe: recipe)],
            contexts: [.init(freeText: " \u{feff}a\0e\u{301}🦭\n")])
        let value = try Candidate(content: content, admission: admission())
        #expect(value.canonicalBytes == Data(Self.golden.utf8))
        #expect(value.unverifiedDigest == "d6386c57a8e3d67c5cb8566fc46dfa59378613ccd0494c85669905df25b2d57a")
        let alternate = try Candidate(content: content, admission: admission(.openAI))
        #expect(alternate.unverifiedDigest != value.unverifiedDigest)
        #expect(content.unverifiedDigest == "d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806")
    }
    @Test func expectationValidationHasNoRecoveryOrProtocolFallback() throws {
        #expect(throws: (any Error).self) { _ = try admission(.recoveryOnly) }
        #expect(throws: (any Error).self) {
            _ = try Admission(authorization: .init(recipient: .gemini, validate: { throw SharedMediaStorageFailure.stale }))
        }
        let saved = try admission()
        for changes: [String: Any] in [["clientProtocol": 2], ["identificationProtocol": 5],
            ["expectedProcessorPermission": "recovery_only"]] {
            let invalid = try Fixture.copy(saved, changes: changes)
            #expect(throws: (any Error).self) { try invalid.validate() }
        }
        #expect(throws: (any Error).self) { try saved.requireSaved(nil) }
        #expect(throws: (any Error).self) { try saved.requireSaved(admission(.openAI)) }
    }
    // Fixed pre-admission-field V2 codec bytes. Nested blobs are deliberately
    // non-admissible placeholders: this characterizes Codable compatibility,
    // not historical graph admission. The disk-backed test covers valid graphs.
    @Test func fixedHistoricalV2CodecOmitsAbsentAdmission() throws {
        let bytes = Data(Self.historicalV2Codec.utf8)
        let saved = try JSONDecoder().decode(Intent.Prepared.self, from: bytes)
        #expect(saved.photoAdmission == nil)
        #expect(try SharedMediaNativeDraftEnvelope.bytes(saved) == bytes)
        #expect(throws: (any Error).self) { _ = try saved.encoded() }
    }
    @Test func absentLegacyFieldAndRequestRoundTripStayExact() async throws {
        let f = try await Fixture.load(count: 1), legacy = try Intent.Prepared(f.request)
        let bytes = try legacy.encoded()
        #expect(try Fixture.object(legacy)["photoAdmission"] == nil)
        #expect(try Intent.Prepared.decode(bytes).encoded() == bytes)
        #expect(throws: (any Error).self) { _ = try Candidate(prepared: legacy) }
        let invalidV1 = try Fixture.copy(legacy, changes: ["photoAdmission": Fixture.object(admission())])
        #expect(throws: (any Error).self) { _ = try invalidV1.encoded() }
        let p = try Fixture.copy(legacy, changes: ["format": "nativeReceivingIntentV2", "version": 2,
            "intentRevision": 0, "photoAdmission": Fixture.object(admission())])
        let transaction = try p.descriptorForTransaction(header: f.request.header)
        let request = SharedMediaNativeAppReceivingRequest(transaction)
        #expect(try Intent.Prepared(request).encoded() == p.encoded())
        let received = try Intent.Received(prepared: p, request: request)
        #expect(try received.reconstruct(p).cohort.intentBinding?.photoAdmission == p.photoAdmission)
        let candidate = try Candidate(prepared: p)
        #expect(try Candidate(prepared: .decode(p.encoded())).canonicalBytes == candidate.canonicalBytes)
        let changed = try Fixture.copy(p, changes: ["photoAdmission": Fixture.object(admission(.openAI))])
        #expect(throws: (any Error).self) { _ = try received.reconstruct(changed) }
    }
    @Test func stagedExpectationSurvivesColdRetryReceivingAndReleaseOrigin() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(temporaryStore: true, fenceBootstrap: true)
        let pairs = try SharedMediaNativeReceivingStagingTests().pairIDs(request), expectation = try admission()
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: pairs, photoAdmission: expectation)
        let bytes = try p.encoded(), candidate = try Candidate(prepared: p)
        await #expect(throws: (any Error).self) {
            _ = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
                pairIDs: pairs, photoAdmission: admission(.openAI))
        }
        #expect(try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: pairs).encoded() == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let saved = try await cold.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: pairs, photoAdmission: expectation)
        #expect(try saved.encoded() == bytes)
        #expect(try Candidate(prepared: saved).canonicalBytes == candidate.canonicalBytes)
        let cohort = try await cold.receiveAppPrepared(saved)
        #expect(cohort.intentBinding?.photoAdmission == expectation)
        let release = try await cold.appReleaseStageRequest(saved, releaseID: UUID())
        let snapshot = try SharedMediaNativeReceivedReleaseSnapshot.read(packageID: h.packageID,
            inventoryID: h.inventoryID, releaseID: release.request.releaseID, context: h.context())
        try snapshot.funding.requireExistingFunding()
        #expect(snapshot.funding.before == (try budget(h)).receivedLiabilityByPackage[h.packageID])
        _ = try await cold.stageAppRelease(release)
        let stagedBudget = try budget(h)
        #expect(stagedBudget.metadataByPackage[h.packageID] != nil)
        #expect(stagedBudget.baseMetadataByPackage[h.packageID] == nil)
        #expect(stagedBudget.receivedLiabilityByPackage[h.packageID] == nil)
        #expect(try await cold.discoverAppRelease(saved) == .staged(release.request))
        // A cold staged request does not recreate the in-memory start right.
        // Keep the staging owner through start and pair removal, then test cold cleanup.
        let started = try await cold.startAppRelease(release.request)
        let retiring = try await cold.retireAppReleasePair(started)
        let pairGone = try await cold.removeAppReleasePair(retiring)
        #expect(try await cold.discoverAppRelease(saved) == .releasing(pairGone))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
        let resumed = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await resumed.discoverAppRelease(saved) == .releasing(pairGone))
        let originalRetiring = try await resumed.disposeAppReleaseOriginal(pairGone)
        let originalGone = try await resumed.removeAppReleaseOriginal(originalRetiring)
        let released = try await resumed.finishAppRelease(originalGone)
        #expect(try await resumed.finishAppRelease(originalGone) == released)
        let context = h.context(), packageID = h.packageID
        #expect(try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID })) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })) == 0)
        try SharedMediaNativeReceivingRows.requireAbsent(.init(originalGone.plan), in: context)
        #expect(try budget(h).metadataByPackage[packageID] == nil)
        #expect(try SharedMediaNativeTerminalScan.read(container: h.container, inventoryID: h.inventoryID).bytes == Int64(released.encoded().count))
        #expect(await resumed.invalidateAndAwaitForAccountTransition())
        let terminal = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await terminal.finishAppRelease(originalGone) == released)
        #expect(try await terminal.discoverAppReceivedCandidates().isEmpty)
        #expect(await terminal.invalidateAndAwaitForAccountTransition())
    }
    private func budget(_ h: SharedMediaNativeAppMetadataTests.Store) throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
        let context = h.context(), inventoryID = h.inventoryID
        let inventory = try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>(
            predicate: #Predicate { $0.id == inventoryID })).first)
        return try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: h.ownerID, format: .appV2)
    }
    private static let historicalV2Codec = #"{"bindingID":"00000000-0000-4000-8000-000000000010","cohort":{"bytes":"e30=","sha256":"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"},"eventID":"00000000-0000-4000-8000-000000000012","format":"nativeReceivingIntentV2","generation":"00000000-0000-4000-8000-000000000011","intentRevision":0,"member":{"bytes":"e30=","draftGeneration":"00000000-0000-4000-8000-000000000006","id":"00000000-0000-4000-8000-000000000005","inventoryGeneration":"00000000-0000-4000-8000-000000000003","inventoryID":"00000000-0000-4000-8000-000000000002","ownerID":"00000000-0000-4000-8000-000000000001","revision":0},"observationID":"00000000-0000-4000-8000-000000000009","operationID":"00000000-0000-4000-8000-000000000007","package":{"allocated":0,"contract":"photo_preparation_v1","draftID":"00000000-0000-4000-8000-000000000005","envelope":"e30=","generation":"00000000-0000-4000-8000-000000000006","id":"00000000-0000-4000-8000-000000000005","ownerID":"00000000-0000-4000-8000-000000000001","phase":"draftOwned","retiring":false,"revision":1,"tier":"pending"},"profile":{"generation":"00000000-0000-4000-8000-000000000003","inventoryID":"00000000-0000-4000-8000-000000000002","ownerID":"00000000-0000-4000-8000-000000000001","physicalBinding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptDigest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","storeIdentity":"00000000-0000-4000-8000-000000000004"},"queueID":"00000000-0000-4000-8000-000000000008","timestampBits":0,"version":2}"#
    private static let golden = #"{"admission":{"client_protocol":3,"expected_processor_permission":"google_gemini","identification_protocol":6},"content_canonical":"{\"contexts\":[{\"text_utf8_base64\":\"IO+7v2EAZcyB8J+mrQo=\"}],\"contract\":\"client_prepared_media_v1\",\"kind\":\"initial_photo\",\"package_id\":\"00000000-0000-4000-8000-000000000002\",\"photos\":[{\"ai\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000004\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"display\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000005\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"ordinal\":0,\"recipe\":{\"camera_vertical_center_bits\":null,\"crop_display_size_bits\":null,\"format\":\"nativeStillImageV1\",\"is_pro\":false,\"offset_x_bits\":\"8000000000000000\",\"offset_y_bits\":\"0000000000000000\",\"quarter_turns\":0,\"scale_bits\":\"3ff0000000000000\"},\"source\":{\"byte_count\":1,\"declared_content_type\":\"image/jpeg\",\"reference_id\":\"00000000-0000-4000-8000-000000000003\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}],\"resource_profile\":\"P1-L1\",\"scan_id\":\"00000000-0000-4000-8000-000000000001\",\"version\":1}","variant":"client_prepared_photo","version":1}"#
}
