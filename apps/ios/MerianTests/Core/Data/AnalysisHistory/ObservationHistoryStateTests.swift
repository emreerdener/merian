import Foundation
import Testing
@testable import Merian

struct ObservationHistoryStateTests {
    func fixture() throws -> [String: Any] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/state-v1.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    func decode(_ fixture: [String: Any], target: String? = nil) throws -> ObservationHistoryState {
        try ObservationHistoryState.decode(JSONSerialization.data(withJSONObject: fixture),
            request: .init(observation_id: "00000000-0000-4000-8000-000000000001", analysis_id: target),
            ownerID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
    }
    @Test func sharedStateBindsSelectedResultAndSeparateAuthority() throws {
        let fixture = try fixture(), state = try decode(fixture)
        #expect(state.revision == 1)
        #expect(state.reviewRevision == 0)
        #expect(state.selectedAnalysisID == state.result.analysisID)
        #expect(state.result.completedAt == nil)
        #expect(state.review.aiReview == nil)
        #expect(state.review.speciesReview == nil)
        #expect(state.review.state == .unreviewed)
        let item = try #require(fixture["analysis"] as? [String: Any])
        #expect(state.result.bytes == Data((item["snapshot"] as! String).utf8))
    }
    @Test func explicitPreviewDoesNotBecomeSelection() throws {
        var value = try fixture()
        let original = try #require(value["selected_analysis_id"] as? String)
        value["selected_analysis_id"] = "00000000-0000-4000-8000-000000000099"
        #expect(throws: (any Error).self) { try decode(value) }
        let state = try decode(value, target: original)
        #expect(state.selectedAnalysisID != state.result.analysisID)
    }
    @Test func malformedAuthorityAndRevisionCannotEnterState() throws {
        let value = try fixture(), item = try #require(value["analysis"] as? [String: Any])
        let review = try #require(item["review_snapshot"] as? [String: Any])
        let invalidStates: [[String: Any]] = [["state_revision": 0], ["state_revision": true], ["selection_initialized": 1],
            ["owner_id": "00000000-0000-4000-8000-000000000099"], ["extra": true]]
        for patch in invalidStates {
            #expect(throws: (any Error).self) { try decode(value.merging(patch) { _, new in new }) }
        }
        let invalidReviews: [[String: Any]] = [["user_confirmed_identification": 1], ["ai_identification_review": [:]],
            ["confirmed_species_identity": [:]], ["confirmed_species_identity_revision": -1],
            ["user_review_state": "confirmed"], ["user_review_state": ["unreviewed"]], ["private_notes": "not authorized"], ["user_identification_override": String(repeating: "a", count: 1025)]]
        for patch in invalidReviews {
            var invalid = value, changed = item
            changed["review_snapshot"] = review.merging(patch) { _, new in new }
            invalid["analysis"] = changed
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
    }
    @Test func nestedAIReviewHasByteAndUTF16BoundsAndPreservesRejection() throws {
        let fixture = try fixture(), item = try #require(fixture["analysis"] as? [String: Any])
        var review = try #require(item["review_snapshot"] as? [String: Any])
        let ai: [String: Any] = ["version": 1, "revision": 2, "state": "ai_rejected",
            "origin_scan_id": "00000000-0000-4000-8000-000000000001",
            "origin_identification": ["scientific_name": "Saved fixture", "common_name": NSNull()],
            "operation_id": NSNull(), "operation_digest": NSNull(), "community": NSNull()]
        review["ai_identification_review"] = ai
        #expect(try ObservationHistoryAuthority.decode(review).aiReview?.state == .aiRejected)
        for label in [String(repeating: "e\u{0301}", count: 100), "e" + String(repeating: "\u{0301}", count: 5000)] {
            var changed = ai
            changed["origin_identification"] = ["scientific_name": label, "common_name": NSNull()]
            review["ai_identification_review"] = changed
            #expect(throws: (any Error).self) { try ObservationHistoryAuthority.decode(review) }
        }
    }

}
