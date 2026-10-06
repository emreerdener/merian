#if DEBUG
import CryptoKit
import Foundation
import SwiftData

extension UITestSeedCoordinator {
    static var publicationConsentEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedPublicationConsentChooser")
    }
    @MainActor static var publicationConsentFixture: PublicationConsentUIFixture?
}

/// Process-local synthetic boundaries; all history, consent and outbox writes
/// still use their production owners. Only the dedicated UI-test seed installs it.
@MainActor final class PublicationConsentUIFixture {
    static let observation = "00000000-0000-4000-8000-000000000001"
    static let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let selected = "00000000-0000-4000-8000-000000000004"
    static let historical = "00000000-0000-4000-8000-000000000002"
    static let media = ["00000000-0000-4000-8000-000000000005", "00000000-0000-4000-8000-000000000006"]
    let container: ModelContainer
    let namedReview: Bool
    let bytes: Data
    let digest: String
    let snapshots: [String: Data]
    let preparation = ObservationPublicationPreparationOwner()
    let recovery = ObservationPublicationRecoveryOwner()
    private var savedOperation: UUID?

    init(container: ModelContainer, namedReview: Bool = ProcessInfo.processInfo.arguments.contains("-seedSelectedNameConfirmation")) throws {
        self.container = container
        self.namedReview = namedReview
        let bytes = try UITestSeedCoordinator.uiTestPNGData()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        self.bytes = bytes; self.digest = digest
        snapshots = try Dictionary(uniqueKeysWithValues: [Self.historical, Self.selected].enumerated().map { index, id in
            let ids = index == 0 ? ["00000000-0000-4000-8000-000000000008"] : Self.media
            let manifest = ids.map { ["kind": "image", "media_id": $0, "content_type": "image/png",
                                      "byte_count": bytes.count, "sha256": digest] as [String: Any] }
            var result: [String: Any] = ["scan_id": Self.observation, "scientific_name": "Danaus plexippus",
                "common_name": "Consent Butterfly", "confidence_score": 0.87, "is_biological_subject": true,
                "is_live_capture": true, "ai_reasoning": "Synthetic identification for photo consent verification.",
                "inference_tier": "flash", "candidates": NSNull(), "pet_identification": NSNull(),
                "blur_score": 0.2, "colors": [], "estimated_size_cm": 8.5,
                "extracted_visual_traits": ["orange wings"],
                "image_quality": ["diagnostic_utility": 9, "framing": 7, "overall_score": 82, "sharpness": 8]]
            if namedReview {
                result["scientific_name"] = "Danaus"
                result["primary_identification"] = ["version": 1, "resolution": "genus", "scientific_name": "Danaus", "common_name": "Consent Butterfly"]
                result["is_new_to_merian_dictionary"] = false
                result["identification_provenance"] = ["version": 2, "provider": "openai", "binding": "synthetic_primary_v1",
                    "model": "gpt-6-sol", "variant": "multimodal", "operation": "scan_identification", "policy_version": 1,
                    "prompt": "synthetic_primary_v1", "schema": "merian_identify_primary_v1", "confidence": "openai_unqualified_v1",
                    "diagnostic_trigger": NSNull(), "prompt_diagnostic_trigger": NSNull(), "safety": "openai_photo_moderation_v1",
                    "timeout_ms": 90_000, "generation": ["max_output_tokens": 8_192, "reasoning_effort": "low", "image_detail": "high"]]
            }
            return (id, try Self.json(["schema_version": 2, "analysis_id": id, "observation_id": Self.observation,
                "ordinal": index + 1, "source_analysis_id": index == 0 ? NSNull() : Self.historical as Any,
                "completed_at_ms": 1_750_000_000_000 + index, "request_digest": String(repeating: "a", count: 64),
                "result": result, "evidence_manifest": ["schema_version": 2, "items": manifest]]))
        })
    }

    func seed(context: ModelContext) throws {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let scan = LocalScanRecord(id: Self.observation, speciesId: "synthetic-consent",
                scientificName: "Danaus plexippus", commonName: "Consent Butterfly", isBiological: true,
                confidenceScore: 0.87, isLocallyArchived: true, hasBeenViewed: true)
            scan.analysisOwnerAccountID = Self.owner.uuidString.lowercased()
            scan.selectedAnalysisID = Self.selected
            scan.analysisSelectionInitialized = true
            scan.observationStateRevision = 0
            context.insert(scan)
            let state = try ObservationHistoryState.decode(stateData(Self.selected),
                request: .init(observation_id: Self.observation, analysis_id: nil), ownerID: Self.owner)
            let old = try ObservationHistoryPage.snapshot(snapshot(Self.historical), observationID: Self.observation, ordinal: 1)
            _ = try ObservationHistorySyncService.insert([old], into: scan, ownerID: Self.owner, context: context)
            try ObservationHistoryStateSyncService.apply(state, to: scan, baseline: .init(scan), context: context)
            if let display = try ObservationHistoryDisplayProjection.snapshot(state.result) {
                try AnalysisDisplaySnapshot.restore(display, analysisID: state.result.analysisID).apply(to: scan)
            }
        }
    }

    var cloud: ObservationHistoryCloudClient {
        .init(begin: { owner in
            guard owner == Self.owner else { throw ObservationHistoryError.accountChanged }
            return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false))
        }, isCurrent: { $0.session.userID == Self.owner && !$0.session.isAnonymous }, finish: { _ in },
        fetch: { [self] request in
            guard request.observation_id == Self.observation, request.before_ordinal == nil, request.limit == 20 else { throw ObservationHistoryError.invalidPage }
            return try Self.json(["schema_version": 1, "owner_id": Self.owner.uuidString.lowercased(),
                "observation_id": Self.observation, "state_revision": 1, "next_before_ordinal": NSNull(),
                "items": try [Self.selected, Self.historical].enumerated().map {
                    ["ordinal": 2 - $0.offset, "snapshot": try snapshotText($0.element)] as [String: Any]
                }])
        }, fetchState: { [self] request in
            guard request.observation_id == Self.observation else { throw ObservationHistoryError.invalidPage }
            return try stateData(request.analysis_id ?? Self.selected)
        })
    }

    func session(_ observation: String, _ candidate: ModelContainer) throws -> IdentificationHistorySession {
        guard observation == Self.observation, candidate === container else { throw ObservationHistoryError.accountChanged }
        let cloud = cloud, bytes = bytes, digest = digest
        let photos = ObservationHistoryPhotoLoader(account: cloud, resolve: { request in
            guard request.observation_id == Self.observation, request.analysis_id == Self.selected,
                  Self.media.contains(request.media_id) else { throw ObservationHistoryError.invalidSnapshot }
            return .init(schema_version: 1, owner_id: Self.owner.uuidString.lowercased(), observation_id: Self.observation,
                analysis_id: Self.selected, media_id: request.media_id, content_type: "image/png", byte_count: bytes.count,
                sha256: digest, url: URL(string: "https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/synthetic")!,
                expires_at_ms: Int64(Date().addingTimeInterval(20).timeIntervalSince1970 * 1_000))
        }, download: { ticket in
            guard ticket.observation_id == Self.observation, ticket.analysis_id == Self.selected,
                  Self.media.contains(ticket.media_id), ticket.sha256 == digest, ticket.byte_count == bytes.count else {
                throw ObservationHistoryError.invalidSnapshot
            }
            return bytes
        })
        let config = IdentificationHistoryPublicationAccess.Configuration(owner: preparation, recoveryOwner: recovery,
            fetchTarget: { request, owner in
                guard owner == Self.owner, request.observationID.uuidString.lowercased() == Self.observation else { throw ObservationHistoryError.accountChanged }
                return nil
            }, fetch: { request, owner in
                guard owner == Self.owner, request.observationID.uuidString.lowercased() == Self.observation,
                      request.analysisID.uuidString.lowercased() == Self.selected else { throw ObservationHistoryError.accountChanged }
                return try .decode(Self.json(["schema_version": 1, "observation_id": Self.observation,
                    "analysis_id": Self.selected, "expected_observation_revision": 1, "expected_review_revision": 0,
                    "taxonomy_version_id": "00000000-0000-4000-8000-000000000007", "initial_taxon_id": NSNull(),
                    "media": Self.media.map { ["media_id": $0, "content_type": "image/png", "byte_count": bytes.count, "sha256": digest] as [String: Any] }]), request: request)
            }, wake: { [self] in
                // This fixture's UI scenario deliberately chooses second, then first.
                // A passing UI cannot conceal a duplicate or reordered durable write.
                assert((try? verifySavedChoice()) == true, "Synthetic consent persistence mismatch")
            }, generation: { 0 })
        return try IdentificationHistorySession(observation: observation, container: candidate, cloud: cloud, photos: photos,
            reviewWake: { [self] in assert((try? verifySavedReview()) == true, "Synthetic review persistence mismatch") }, publication: config, currentGeneration: { 1 },
            sessionIsCurrent: { $0.userID == Self.owner && !$0.isAnonymous })
    }

    private func verifySavedReview() throws -> Bool {
        guard namedReview else { return false }
        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter { $0.kind == .observationAnalysisReviewSync }
        guard jobs.count == 1, let text = jobs.first?.metadataJSON else { return false }
        let intent = try ObservationAnalysisReviewIntent.decode(Data(text.utf8))
        let request = intent.request
        guard request.decision == .confirmName("Danaus plexippus"), request.analysisID.uuidString.lowercased() == Self.selected,
              request.expectedObservationRevision == 1, request.expectedReviewRevision == 0 else { return false }
        return try ObservationHistorySyncService.enrolledScan(Self.observation, context: context).selectedAnalysisID == Self.selected
    }
    private func verifySavedChoice() throws -> Bool {
        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter { $0.kind == .observationPublicationSync }
        guard jobs.count == 1, let text = jobs.first?.metadataJSON else { return false }
        let intent = try ObservationPublicationIntent.decode(Data(text.utf8))
        guard let request = intent.request, request.mediaIDs.map({ $0.uuidString.lowercased() }) == Array(Self.media.reversed()),
              request.note == nil, request.analysisID.uuidString.lowercased() == Self.selected else { return false }
        if let savedOperation { guard savedOperation == request.operationID else { return false } }
        savedOperation = request.operationID
        return try ObservationHistorySyncService.enrolledScan(Self.observation, context: context).selectedAnalysisID == Self.selected
    }
    private func snapshot(_ id: String) throws -> Data {
        guard let data = snapshots[id] else { throw ObservationHistoryError.invalidSnapshot }; return data
    }
    private func snapshotText(_ id: String) throws -> String {
        guard let text = String(data: try snapshot(id), encoding: .utf8) else { throw ObservationHistoryError.invalidSnapshot }
        return text
    }
    private func stateData(_ id: String) throws -> Data {
        try Self.json(["schema_version": 1, "owner_id": Self.owner.uuidString.lowercased(), "observation_id": Self.observation,
            "state_revision": 1, "selection_initialized": true, "selected_analysis_id": Self.selected,
            "analysis": ["snapshot": try snapshotText(id), "review_revision": 0,
                "review_snapshot": ["ai_identification_review": NSNull(), "confirmed_species_identity": NSNull(),
                    "confirmed_species_identity_revision": 0, "confirmed_species_id": NSNull(), "user_identification_override": NSNull(),
                    "user_confirmed_identification": false, "user_review_state": "unreviewed"]]])
    }
    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
#endif
