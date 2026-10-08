import Foundation
@testable import Merian
import Testing

@MainActor
struct ObservationAnalysisReviewTicketTests {
    func ticket(biological: Any = true, primary: PrimaryIdentification.Snapshot? = nil,
                authorityPatch: [String: Any] = [:], revision: Int? = 0, resultPatch: [String: Any] = [:], version: Int = 3, photos: [ObservationHistoryPhotoReference] = [], omittedResultKeys: [String] = []) throws -> ObservationAnalysisReviewTicket {
        let fixture = try ObservationHistoryStateTests().fixture()
        let state = try ObservationHistoryStateTests().decode(fixture)
        var envelope = try version == 4 ? ObservationHistorySyncTests().audioSnapshot() : #require(JSONSerialization.jsonObject(with: state.result.bytes) as? [String: Any])
        envelope["observation_id"] = state.observationID.uuidString.lowercased()
        envelope["analysis_id"] = state.result.analysisID.uuidString.lowercased()
        var result = try #require(envelope["result"] as? [String: Any])
        result["is_biological_subject"] = biological
        if version == 4, let primary {
            result["scientific_name"] = primary.scientificName ?? NSNull()
            result["common_name"] = primary.commonName ?? NSNull()
            result["identification_provenance"] = VerifiedReviewFixtures.history()["identification_provenance"]
        }
        result["primary_identification"] = try primary.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        result.merge(resultPatch) { _, next in next }
        for key in omittedResultKeys { result.removeValue(forKey: key) }
        envelope["schema_version"] = version
        envelope["result"] = result
        var authority = try #require(JSONSerialization.jsonObject(with: state.review.data) as? [String: Any])
        authority.merge(authorityPatch) { _, new in new }
        let encoded = try JSONSerialization.data(withJSONObject: envelope)
        let raw = try version == 4 ? ObservationHistoryPage.snapshot(encoded, observationID: state.observationID.uuidString.lowercased(), ordinal: ObservationHistoryPage.integer(envelope["ordinal"])) : ObservationHistoryPage.Result(version: version, photos: photos, audio: nil, analysisID: state.result.analysisID,
            completedAt: nil, importedAt: state.result.importedAt, bytes: encoded)
        let entry = ObservationHistoryListingService.Entry(result: raw, display: nil,
            authority: try ObservationHistoryAuthority.decode(authority), reviewRevision: revision)
        return try .init(entry: entry, context: .init(owner: state.ownerID, selected: state.selectedAnalysisID,
            revision: state.revision, pendingOperation: nil, undoOperation: nil), observationID: state.observationID)
    }

    @Test func audioReviewUsesExactReader10TicketWithoutPhotoOrCandidatePermission() throws {
        let primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: "Synthetic species", commonName: nil)
        let saved = try ticket(primary: primary, version: 4)
        #expect(saved.canReject && saved.canConfirmPrimary && saved.canConfirmName)
        #expect(saved.evidencePhotoID == nil && saved.candidateChoices.isEmpty && !saved.supportsPhotoPublicationFormat)
        #expect(try saved.request(.reject, operationID: UUID()).analysisID == saved.analysisID)
        #expect(try saved.request(.confirmPrimary, operationID: UUID()).expectedReviewRevision == saved.reviewRevision)
        #expect(try saved.request(.confirmName("Synthetic correction"), operationID: UUID()).analysisID == saved.analysisID)
    }

    @Test func confidenceUsesSavedProvenanceAndPhotoIdentity() throws {
        let photo = ObservationHistoryPhotoReference(mediaID: UUID(), contentType: "image/jpeg", byteCount: 7, sha256: String(repeating: "a", count: 64))
        let saved = try ticket(resultPatch: ["inference_tier": "pro"], version: 2, photos: [photo], omittedResultKeys: ["identification_provenance"])
        #expect(saved.candidateConfidenceQualified && saved.evidencePhotoID == photo.mediaID)
        for malformed: Any in [NSNull(), "invalid", [:], ["provider": "unknown"]] {
            let saved = try ticket(resultPatch: ["inference_tier": "pro", "identification_provenance": malformed])
            #expect(!saved.candidateConfidenceQualified)
        }
        #expect(try ticket().evidencePhotoID == nil)
    }

    @Test func explicitBiologicalV3CanRejectWithoutManufacturingConfirmation() throws {
        let ticket = try ticket()
        #expect(ticket.canReject && !ticket.canConfirmPrimary && !ticket.canConfirmName)
        let operation = UUID(), request = try ticket.request(.reject, operationID: operation)
        #expect(request.operationID == operation && request.analysisID == ticket.analysisID)
        #expect(request.expectedObservationRevision == 1 && request.expectedReviewRevision == 0)
        #expect(throws: (any Error).self) { try ticket.request(.confirmPrimary, operationID: UUID()) }
        #expect(throws: (any Error).self) { try ticket.request(.undo(rejectionOperationID: UUID()), operationID: UUID()) }
    }

    @Test func candidateChoicesRetainRawOrdinalAndRejectUnsupportedEvidence() throws {
        let primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: "Synthetic primary", commonName: nil)
        let first: [String: Any] = ["taxon_rank": "species", "scientific_name": "Synthetic same", "confidence_score": 0.4]
        let second: [String: Any] = ["taxon_rank": "species", "scientific_name": "Synthetic same", "confidence_score": 0.2]
        let reviewed = try ticket(primary: primary, resultPatch: ["candidates": [first, second]], version: 2)
        #expect(reviewed.candidateChoices.map(\.reference.ordinal) == [0, 1])
        #expect(reviewed.candidateChoices[0].reference != reviewed.candidateChoices[1].reference)
        let chosen = reviewed.candidateChoices[1].reference
        #expect(try reviewed.request(.confirmCandidate(chosen), operationID: UUID()).decision == .confirmCandidate(chosen))
        let forged = try ObservationAnalysisCandidateReference(analysisID: reviewed.analysisID, ordinal: 1, scientificName: "Synthetic forged")
        #expect(throws: (any Error).self) { try reviewed.request(.confirmCandidate(forged), operationID: UUID()) }
        #expect(try ticket(primary: primary, resultPatch: ["candidates": [first]], version: 1).candidateChoices.count == 1)
        #expect(try ticket(primary: primary, resultPatch: ["candidates": [first]], version: 3).candidateChoices.isEmpty)
        #expect(try ticket(resultPatch: ["candidates": [first]], version: 2).candidateChoices.isEmpty)
        for candidates: Any in [[], [first, second, first], ["bad"], NSNull(), [first.merging(["taxon_rank": NSNull()]) { _, next in next }],
            [first.merging(["confidence_score": true]) { _, next in next }], [first.merging(["confidence_score": 2]) { _, next in next }]] {
            #expect(try ticket(primary: primary, resultPatch: ["candidates": candidates], version: 2).candidateChoices.isEmpty)
        }
        let filtered = try ticket(primary: primary, resultPatch: ["candidates": [first.merging(["scientific_name": ""]) { _, next in next }, second]], version: 2)
        #expect(filtered.candidateChoices.map(\.reference.ordinal) == [1])
    }

    @Test func numericTrueMissingBiologyAndMissingRevisionNeverAuthorize() throws {
        for value: Any in [false, 1, "true", NSNull()] {
            let ticket = try ticket(biological: value)
            #expect(!ticket.canReject && !ticket.canConfirmPrimary && !ticket.canConfirmName)
        }
        #expect(throws: (any Error).self) { try ticket(revision: nil) }
    }

    @Test(arguments: PrimaryIdentification.Resolution.allCases)
    func confirmationRequiresExplicitRankOrExplicitValidatedName(resolution: PrimaryIdentification.Resolution) throws {
        let primary = try PrimaryIdentification.Snapshot(resolution: resolution,
            scientificName: resolution.isNamedBiologicalTaxon ? "Synthetic taxon" : nil, commonName: nil)
        let ticket = try ticket(primary: primary)
        #expect(ticket.canConfirmPrimary == (resolution == .species))
        #expect(ticket.canConfirmName)
        #expect(try ticket.request(.confirmName("Synthetic species"), operationID: UUID()).decision == .confirmName("Synthetic species"))
        for name in ["", " padded", String(repeating: "e\u{301}", count: 100)] {
            #expect(throws: (any Error).self) { try ticket.request(.confirmName(name), operationID: UUID()) }
        }
    }

    @Test func manualOverrideDoesNotBecomeRejectAndLongPrimaryDoesNotBecomeValidName() throws {
        let manual = try ticket(authorityPatch: ["user_review_state": "user_overridden"])
        #expect(!manual.canReject)
        let primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: String(repeating: "a", count: 161), commonName: nil)
        let ticket = try ticket(primary: primary)
        #expect(!ticket.canConfirmPrimary && ticket.canConfirmName)
    }

    @Test(arguments: [3, 4]) func communityAuthorityCannotAuthorizePrivateConfirmationOrRejection(version: Int) throws {
        let base = try ticket(), primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: "Synthetic species", commonName: nil)
        let ai: [String: Any] = ["version": 1, "revision": 1, "state": "clear", "origin_scan_id": NSNull(),
            "origin_identification": NSNull(), "operation_id": NSNull(), "operation_digest": NSNull(),
            "community": ["request_id": UUID().uuidString.lowercased(), "rank": "genus", "scientific_name": "Synthetic",
                          "common_name": NSNull(), "species_id": NSNull()]]
        let reviewed = try ticket(primary: primary, authorityPatch: ["ai_identification_review": ai], version: version)
        #expect(reviewed.ownerID == base.ownerID)
        #expect(!reviewed.canReject && !reviewed.canConfirmName && !reviewed.canConfirmPrimary && reviewed.rejectionOperationID == nil)
    }

    @Test func rejectionAssociationAloneIsOnlyACandidateForReceiptLookup() throws {
        let operation = UUID(), base = try ticket()
        let ai = AIIdentificationReview(revision: 1, state: .aiRejected, originScanID: base.observationID.uuidString.lowercased(),
            originIdentification: nil, operationID: operation.uuidString.lowercased())
        let ticket = try ticket(authorityPatch: ["ai_identification_review": JSONSerialization.jsonObject(with: ai.storedData())])
        #expect(!ticket.canReject && ticket.rejectionOperationID == operation)
        #expect(try ticket.request(.undo(rejectionOperationID: operation), operationID: UUID()).expectedReviewRevision == 0)
    }
}
