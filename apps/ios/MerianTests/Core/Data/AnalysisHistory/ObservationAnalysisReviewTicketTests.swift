import Foundation
@testable import Merian
import Testing

@MainActor
struct ObservationAnalysisReviewTicketTests {
    func ticket(biological: Any = true, primary: PrimaryIdentification.Snapshot? = nil,
                authorityPatch: [String: Any] = [:], revision: Int? = 0) throws -> ObservationAnalysisReviewTicket {
        let fixture = try ObservationHistoryStateTests().fixture()
        let state = try ObservationHistoryStateTests().decode(fixture)
        var envelope = try #require(JSONSerialization.jsonObject(with: state.result.bytes) as? [String: Any])
        var result = try #require(envelope["result"] as? [String: Any])
        result["is_biological_subject"] = biological
        result["primary_identification"] = try primary.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
        envelope["result"] = result
        var authority = try #require(JSONSerialization.jsonObject(with: state.review.data) as? [String: Any])
        authority.merge(authorityPatch) { _, new in new }
        let raw = ObservationHistoryPage.Result(version: 3, photos: [], analysisID: state.result.analysisID,
            completedAt: nil, importedAt: state.result.importedAt, bytes: try JSONSerialization.data(withJSONObject: envelope))
        let entry = ObservationHistoryListingService.Entry(result: raw, display: nil,
            authority: try ObservationHistoryAuthority.decode(authority), reviewRevision: revision)
        return try .init(entry: entry, context: .init(owner: state.ownerID, selected: state.selectedAnalysisID,
            revision: state.revision, pendingOperation: nil, undoOperation: nil), observationID: state.observationID)
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

    @Test func communityAuthorityCannotAuthorizePrivateConfirmationOrRejection() throws {
        let base = try ticket(), primary = try PrimaryIdentification.Snapshot(resolution: .species, scientificName: "Synthetic species", commonName: nil)
        let ai: [String: Any] = ["version": 1, "revision": 1, "state": "clear", "origin_scan_id": NSNull(),
            "origin_identification": NSNull(), "operation_id": NSNull(), "operation_digest": NSNull(),
            "community": ["request_id": UUID().uuidString.lowercased(), "rank": "genus", "scientific_name": "Synthetic",
                          "common_name": NSNull(), "species_id": NSNull()]]
        let reviewed = try ticket(primary: primary, authorityPatch: ["ai_identification_review": ai])
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
