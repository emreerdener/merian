import CoreFoundation
import CryptoKit
import Foundation

/// Value captured when a preview is admitted. Display labels never authorize a
/// review; immutable evidence and the separately acknowledged authority do.
struct ObservationAnalysisReviewTicket: Equatable {
    let ownerID: UUID
    let observationID: UUID
    let analysisID: UUID
    let selectedAnalysisID: UUID
    let observationRevision: Int
    let reviewRevision: Int
    let primaryScientificName: String?
    let canReject: Bool
    let canConfirmPrimary: Bool
    let canConfirmName: Bool
    let candidateChoices: [ObservationAnalysisCandidateChoice]
    let rejectionOperationID: UUID?
    let confirmationOperationID: UUID?
    let confirmationAction: ObservationConfirmationAction?
    let reviewState: UserReviewState?
    let correctionName: String?
    private let resultDigest: Data
    private let authorityDigest: Data

    init(entry: ObservationHistoryListingService.Entry, context: ObservationHistoryListingService.Context,
         observationID: UUID) throws {
        guard let authority = entry.authority, let reviewRevision = entry.reviewRevision,
              context.revision > 0, reviewRevision >= 0, reviewRevision <= context.revision else {
            throw ObservationHistoryError.unavailable
        }
        let envelope = try JSONSerialization.jsonObject(with: entry.result.bytes) as? [String: Any]
        guard envelope?["observation_id"] as? String == observationID.uuidString.lowercased(),
              envelope?["analysis_id"] as? String == entry.result.analysisID.uuidString.lowercased(),
              let result = envelope?["result"] as? [String: Any] else { throw ObservationHistoryError.invalidSnapshot }
        let biological = (result["is_biological_subject"] as? NSNumber).map {
            CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue
        } ?? false
        let primary: PrimaryIdentification.Snapshot?
        if let raw = result["primary_identification"], !(raw is NSNull) {
            primary = try JSONDecoder().decode(PrimaryIdentification.Snapshot.self, from: JSONSerialization.data(withJSONObject: raw))
        } else { primary = nil }
        let available = biological && authority.aiReview?.community == nil
            && (authority.aiReview?.revision ?? 0) < 999_999_999 && authority.identityRevision < 2_147_483_646
            && context.revision < 2_147_483_647 && reviewRevision < 2_147_483_647
        ownerID = context.owner; self.observationID = observationID; analysisID = entry.result.analysisID
        selectedAnalysisID = context.selected; observationRevision = context.revision; self.reviewRevision = reviewRevision
        primaryScientificName = primary?.scientificName
        canReject = available && authority.state != .userOverridden && (authority.aiReview?.state ?? .clear) == .clear
        canConfirmName = available && primary != nil
        candidateChoices = available && (try? ObservationAnalysisReviewWire.integer(envelope?["schema_version"])) == entry.result.version
            ? ObservationAnalysisCandidateChoice.extract(result: result, version: entry.result.version, analysisID: entry.result.analysisID) : []
        // Reuse the exact explicit-name wire validator, including UTF-16 bounds.
        canConfirmPrimary = available && primary?.resolution == .species && primary?.scientificName.map {
            (try? ObservationAnalysisReviewRequest(observationID: observationID, analysisID: entry.result.analysisID,
                operationID: observationID, expectedObservationRevision: context.revision,
                expectedReviewRevision: reviewRevision, decision: .confirmName($0))) != nil
        } == true
        rejectionOperationID = available && authority.state != .userOverridden && authority.aiReview?.state == .aiRejected
            ? authority.aiReview?.operationID.flatMap(UUID.init(uuidString:)) : nil
        reviewState = authority.state; correctionName = authority.override
        confirmationAction = available && (authority.aiReview?.state ?? .clear) == .clear
            ? (authority.state == .aiConfirmed ? .primary : (authority.state == .userOverridden ? .name : nil)) : nil
        confirmationOperationID = confirmationAction != nil ? authority.aiReview?.operationID.flatMap(UUID.init(uuidString:)) : nil
        resultDigest = Data(SHA256.hash(data: entry.result.bytes))
        authorityDigest = Data(SHA256.hash(data: authority.data))
    }

    /// Call synchronously at the actual tap and retain the returned request across
    /// uncertain saves. Rejection Undo needs its local receipt; confirmation Undo
    /// also admits strictly recovered eligibility in the staging transaction.
    func request(_ decision: ObservationAnalysisReviewRequest.Decision, operationID: UUID) throws -> ObservationAnalysisReviewRequest {
        let allowed: Bool
        switch decision {
        case .reject: allowed = canReject
        case .confirmPrimary: allowed = canConfirmPrimary
        case .confirmName: allowed = canConfirmName
        case let .confirmCandidate(reference): allowed = canConfirmName && candidateChoices.contains { $0.reference == reference }
        case let .undoConfirmation(operation): allowed = confirmationOperationID == operation && confirmationAction != nil
        case let .undo(rejectionID): allowed = rejectionOperationID == rejectionID
        }
        guard allowed else { throw ObservationHistoryError.unavailable }
        return try .init(observationID: observationID, analysisID: analysisID, operationID: operationID,
            expectedObservationRevision: observationRevision, expectedReviewRevision: reviewRevision, decision: decision)
    }
}
