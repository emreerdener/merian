import Foundation
import Supabase

extension MerianNetworkClient {
    func reviewScanIdentification(_ request: AIIdentificationReviewRequest) async throws -> AIIdentificationReviewReceipt {
        let data = try await performAuthenticatedEncodedJSONPost(function: "review-scan-identification", body: request,
            timeoutInterval: 30, allowsUnauthorizedSessionRecovery: false)
        guard data.count <= 16_384 else { throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope }
        let receipt = try JSONDecoder().decode(AIIdentificationReviewReceipt.self, from: data)
        guard receipt.schemaVersion == 1, receipt.scanID == request.scanID,
              receipt.review.operationID == request.operationID,
              receipt.review.revision == request.expectedRevision + 1 else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
        }
        return receipt
    }
}

/// Caller-owned snapshot used to reconcile conflicts without replaying stale intent.
struct AIIdentificationReviewSnapshot: Decodable, Sendable {
    let scan_id: String
    let review: AIIdentificationReview?
    let review_fields: Fields
    struct Fields: Decodable, Sendable {
        let confirmed_species_id: String?
        let user_identification_override: String?
        let user_confirmed_identification: Bool
        let user_review_state: UserReviewState
        let confirmed_species_identity: ConfirmedSpeciesReview.Identity?
        let confirmed_species_identity_revision: Int
    }
    @MainActor static func fetch(scanID: String) async throws -> Self {
        struct Lookup: Encodable { let p_scan_ids: [String] }
        let data = try await SupabaseManager.shared.client.rpc("get_owned_scan_ai_reviews", params: Lookup(p_scan_ids: [scanID])).execute().data
        let rows = try JSONDecoder().decode([Self].self, from: data)
        guard let result = rows.first, rows.count == 1, result.scan_id.lowercased() == scanID.lowercased() else {
            throw ConfirmedSpeciesReview.IntegrityError.missingRecord
        }
        return result
    }
}
