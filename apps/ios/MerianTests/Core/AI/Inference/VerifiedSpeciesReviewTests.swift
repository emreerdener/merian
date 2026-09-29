import Foundation
import SwiftData
import Testing
@testable import Merian

/// Synthetic authority fixtures exercise the dormant contract without providers.
enum VerifiedReviewFixtures {
    static let scanID = "10000000-0000-4000-8000-000000000001"
    static let speciesID = "20000000-0000-4000-8000-000000000001"
    static func review(_ revision: Int = 1, name: String? = "Examplea testus") -> [String: Any] {
        let identity: Any = name.map { ["version": 1, "species_id": speciesID, "scientific_name": $0,
                                      "common_name": NSNull(), "gbif_taxon_key": 123] as [String: Any] } as Any? ?? NSNull()
        return ["version": 1, "revision": revision, "identity": identity,
         "user_identification_override": name as Any? ?? NSNull(), "user_confirmed_identification": false,
         "confirmed_species_id": name == nil ? NSNull() : speciesID,
         "user_review_state": name == nil ? "unreviewed" : "user_overridden"]
    }
    static func decode(_ payload: [String: Any]) throws -> ConfirmedSpeciesReview {
        try JSONDecoder().decode(ConfirmedSpeciesReview.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    static func history(_ review: [String: Any]? = nil) -> [String: Any] {
        var row: [String: Any] = ["id": scanID, "timestamp": "2026-09-29T12:00:00Z", "explore_posts": NSNull(),
            "ai_confidence_score": 0.42, "ai_reasoning": "Original evidence", "is_biological_subject": true,
            "primary_identification": ["version": 1, "resolution": "genus", "scientific_name": "Examplea", "common_name": "Example"],
            "identification_provenance": ["version": 2, "provider": "openai", "binding": "synthetic_primary_v1",
             "model": "gpt-6-sol", "variant": "multimodal", "operation": "scan_identification", "policy_version": 1,
             "prompt": "synthetic_primary_v1", "schema": "merian_identify_primary_v1", "confidence": "openai_unqualified_v1",
             "diagnostic_trigger": NSNull(), "prompt_diagnostic_trigger": NSNull(), "safety": "openai_photo_moderation_v1",
             "timeout_ms": 90_000, "generation": ["max_output_tokens": 8_192, "reasoning_effort": "low", "image_detail": "high"]]]
        if let review {
            row["confirmed_species_identity"] = review["identity"]
            row["confirmed_species_identity_revision"] = review["revision"]
            for key in ["user_identification_override", "user_confirmed_identification", "confirmed_species_id", "user_review_state"] {
                row[key] = review[key]
            }
        }
        return row
    }
    static func row(_ payload: [String: Any]) throws -> HistoricalScanResponse {
        try JSONDecoder().decode(HistoricalScanResponse.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    static func primary(_ resolution: PrimaryIdentification.Resolution = .genus) throws -> PrimaryIdentification {
        try PrimaryIdentification(snapshot: .init(resolution: resolution, scientificName: "Examplea", commonName: "Example"))
    }
}

@MainActor
struct VerifiedSpeciesReviewTests {
    @Test func selectedSpeciesStaysSeparateFromPrimaryPresentationAndEnrichment() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = HistoricalDatabaseActor(modelContainer: context.container)
        try await actor.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(VerifiedReviewFixtures.review()))])
        let record = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        let projection = InferenceHistoricalRecordProjection(record: record, resetLocalLookalikes: false)
        var displayed = projection.speciesData
        #expect(displayed.verifiedConfirmedSpeciesIdentity?.scientificName == "Examplea testus")
        #expect(displayed.scientificName == "Examplea" && displayed.confidenceScore == 0.42)
        #expect(!displayed.hasSpeciesLevelIdentification && !projection.hydrationPlan.allowsSpeciesHydration)
        #expect(record.effectiveSpeciesNameForStatistics == "Examplea testus")
        #expect(displayed.isShareableBiologicalObservation)
        displayed.userIdentificationOverride = "Pending replacement"
        #expect(displayed.verifiedConfirmedSpeciesIdentity == nil)
        displayed.confirmedSpeciesReview = try VerifiedReviewFixtures.decode(VerifiedReviewFixtures.review(2, name: nil))
        displayed.userIdentificationOverride = nil
        #expect(displayed.verifiedConfirmedSpeciesIdentity == nil)
        #expect(displayed.scientificName == "Examplea" && displayed.confidenceScore == 0.42)
    }

    @Test func requestsContainOnlySelectionAndExpectedRevision() throws {
        let mutation = InferenceIdentificationReviewMutation.userOverride(
            scanID: VerifiedReviewFixtures.scanID.uppercased(), scientificName: "Examplea testus", confirmedSpeciesID: "untrusted-id")
        let request = try VerifiedSpeciesReviewRequest(mutation: mutation, revision: 7, primary: VerifiedReviewFixtures.primary())
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(Set(encoded.keys) == ["scan_id", "action", "expected_revision", "scientific_name"])
        #expect(encoded["expected_revision"] as? Int == 7)
        #expect(encoded["action"] as? String == "confirm_name")
        for mutation in [InferenceIdentificationReviewMutation.reset(scanID: VerifiedReviewFixtures.scanID),
                         .aiConfirmation(scanID: VerifiedReviewFixtures.scanID, confirmedSpeciesID: "ignored")] {
            let request = try VerifiedSpeciesReviewRequest(mutation: mutation, revision: 0, primary: VerifiedReviewFixtures.primary(.species))
            let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
            #expect(Set(encoded.keys) == ["scan_id", "action", "expected_revision"])
        }
        #expect(throws: Error.self) {
            try VerifiedSpeciesReviewRequest(mutation: .aiConfirmation(scanID: VerifiedReviewFixtures.scanID, confirmedSpeciesID: nil),
                                             revision: 0, primary: VerifiedReviewFixtures.primary())
        }
    }

    @Test func receiptRejectsMalformedAuthorityAndWrongAcknowledgement() throws {
        let valid = VerifiedReviewFixtures.review()
        let invalid: [[String: Any]] = [
            ["version": 2], ["revision": -1], ["revision": 2_147_483_648], ["revision": 0],
            ["user_confirmed_identification": true], ["confirmed_species_id": NSNull()],
            ["user_review_state": "unreviewed"], ["user_identification_override": ""], ["extra": true]
        ]
        for change in invalid {
            #expect(throws: Error.self) { try VerifiedReviewFixtures.decode(valid.merging(change) { _, new in new }) }
        }
        for key in valid.keys {
            var missing = valid; missing.removeValue(forKey: key)
            #expect(throws: Error.self) { try VerifiedReviewFixtures.decode(missing) }
        }
        let identityMutations: [[String: Any]] = [["common_name": "unadmitted"], ["species_id": "not-a-uuid"],
            ["scientific_name": String(repeating: "x", count: 161)], ["scientific_name": "bad\nname"],
            ["gbif_taxon_key": 0], ["gbif_taxon_key": true], ["version": 2], ["extra": true]]
        for change in identityMutations {
            var payload = valid
            payload["identity"] = try #require(valid["identity"] as? [String: Any]).merging(change) { _, new in new }
            #expect(throws: Error.self) { try VerifiedReviewFixtures.decode(payload) }
        }
        let receipt = try JSONDecoder().decode(VerifiedSpeciesReviewReceipt.self, from: JSONSerialization.data(withJSONObject:
            ["schema_version": 1, "scan_id": VerifiedReviewFixtures.scanID, "review": valid]))
        let request = try VerifiedSpeciesReviewRequest(mutation: .reset(scanID: VerifiedReviewFixtures.scanID), revision: 0,
                                                      primary: VerifiedReviewFixtures.primary())
        #expect(throws: Error.self) { try request.validate(receipt) }
    }

    @Test func historyDistinguishesAbsentClearAndPartialProjection() throws {
        #expect(try VerifiedReviewFixtures.row(VerifiedReviewFixtures.history()).confirmedSpeciesReview == nil)
        let clear = try VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(VerifiedReviewFixtures.review(3, name: nil)))
        #expect(clear.confirmedSpeciesReview?.revision == 3)
        #expect(clear.confirmedSpeciesReview?.identity == nil)
        let bytes = try #require(try clear.confirmedSpeciesReview?.storedData())
        #expect(try ConfirmedSpeciesReview.restoring(bytes) == clear.confirmedSpeciesReview)
        var malformed = VerifiedReviewFixtures.history(VerifiedReviewFixtures.review())
        malformed.removeValue(forKey: "confirmed_species_identity_revision")
        let page = try HistoricalScanPageDecoder.decode(JSONSerialization.data(withJSONObject: [malformed, VerifiedReviewFixtures.history()]))
        #expect(page.remoteRowCount == 2 && page.rejectedRowCount == 1 && page.responses.count == 1)
        #expect(throws: Error.self) { try VerifiedReviewFixtures.row(malformed) }
        let legacy: [String: Any] = ["id": "legacy", "confirmed_species_identity": NSNull(),
            "confirmed_species_identity_revision": 0, "confirmed_species_id": "legacy-selection"]
        #expect(try VerifiedReviewFixtures.row(legacy).confirmedSpeciesReview == nil)
    }

    @Test func historyReplacementClearStaleAndRecoveryPreserveAIAnswer() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = HistoricalDatabaseActor(modelContainer: context.container)
        func saved() throws -> LocalScanRecord {
            try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        }
        #expect(try await actor.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(VerifiedReviewFixtures.review()))]) == 1)
        #expect(try saved().verifiedConfirmedSpeciesIdentity?.scientificName == "Examplea testus")
        let replacement = VerifiedReviewFixtures.review(2, name: "Examplea altera")
        try await actor.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(replacement))])
        #expect(try saved().verifiedConfirmedSpeciesIdentity?.scientificName == "Examplea altera")
        let clear = VerifiedReviewFixtures.review(3, name: nil)
        try await actor.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(clear))])
        try await actor.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(replacement))])
        try await actor.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history())])
        let record = try saved()
        #expect(record.confirmedSpeciesReview?.revision == 3 && record.verifiedConfirmedSpeciesIdentity == nil)
        #expect(record.userIdentificationOverride == nil && !record.userConfirmedIdentification && record.confirmedSpeciesId == nil)
        #expect(record.scientificName == "Examplea" && record.aiReasoning == "Original evidence" && record.confidenceScore == 0.42)
        #expect(!record.hasSpeciesLevelIdentification)
        let sameRevisionConflict = VerifiedReviewFixtures.review(3)
        await #expect(throws: Error.self) {
            try await actor.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(sameRevisionConflict))])
        }
        #expect(try saved().confirmedSpeciesReview?.revision == 3)
        // A missing local row is restored exclusively from the current owned server projection.
        let removal = ModelContext(context.container)
        for row in try removal.fetch(FetchDescriptor<LocalScanRecord>()) { removal.delete(row) }
        try removal.save()
        let recovery = HistoricalDatabaseActor(modelContainer: context.container)
        #expect(try await recovery.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(clear))]) == 1)
        #expect(try saved().confirmedSpeciesReview?.revision == 3 && saved().confirmedSpeciesId == nil)
    }

    @Test func pendingIntentHasNoAuthorityAndEqualHistoryDoesNotEraseIt() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let history = HistoricalDatabaseActor(modelContainer: context.container)
        let row = try VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(VerifiedReviewFixtures.review()))
        try await history.reconcileScanPage(responses: [row])
        let mutation = InferenceIdentificationReviewMutation.userOverride(scanID: VerifiedReviewFixtures.scanID,
            scientificName: "Examplea altera", confirmedSpeciesID: "forged")
        let actor = BackgroundDatabaseActor(modelContainer: context.container)
        let request = try await actor.prepareVerifiedSpeciesReview(mutation)
        #expect(request.expectedRevision == 1)
        try await HistoricalDatabaseActor(modelContainer: context.container).reconcileScanPage(responses: [row])
        let pending = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(pending.userIdentificationOverride == "Examplea altera")
        #expect(pending.confirmedSpeciesReview?.identity?.scientificName == "Examplea testus")
        #expect(pending.verifiedConfirmedSpeciesIdentity == nil && pending.confirmedSpeciesId == nil)
        let review = try VerifiedReviewFixtures.decode(VerifiedReviewFixtures.review(2, name: "Examplea altera"))
        #expect(try await actor.applyVerifiedSpeciesReview(scanID: mutation.scanID, review: review, acknowledging: mutation) == review)
        let reopened = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(reopened.verifiedConfirmedSpeciesIdentity?.scientificName == "Examplea altera")
    }

    @Test(arguments: [false, true])
    func independentContextsAlwaysRetainNewestReviewAndWholeTuple(newestIsClear: Bool) async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let history = HistoricalDatabaseActor(modelContainer: context.container)
        let endpoint = BackgroundDatabaseActor(modelContainer: context.container)
        try await history.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(VerifiedReviewFixtures.review()))])
        let mutation = InferenceIdentificationReviewMutation.userOverride(scanID: VerifiedReviewFixtures.scanID,
            scientificName: "Examplea altera", confirmedSpeciesID: nil)
        _ = try await endpoint.prepareVerifiedSpeciesReview(mutation)
        let newer = try VerifiedReviewFixtures.decode(VerifiedReviewFixtures.review(3, name: newestIsClear ? nil : "Examplea ultima"))
        _ = try await endpoint.applyVerifiedSpeciesReview(scanID: mutation.scanID, review: newer, acknowledging: nil)
        // Reuse the history actor that previously fetched revision one.
        try await history.reconcileScanPage(responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(VerifiedReviewFixtures.review(2)))])
        // Reuse the endpoint actor after a different history context advances again.
        let newest = VerifiedReviewFixtures.review(4, name: newestIsClear ? nil : "Examplea finalis")
        try await HistoricalDatabaseActor(modelContainer: context.container).reconcileScanPage(
            responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(newest))])
        let returned = try await endpoint.applyVerifiedSpeciesReview(scanID: mutation.scanID, review: newer, acknowledging: nil)
        #expect(returned == (try VerifiedReviewFixtures.decode(newest)))
        let record = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(record.confirmedSpeciesReview == (try VerifiedReviewFixtures.decode(newest)))
        #expect(record.userIdentificationOverride == (newestIsClear ? nil : "Examplea finalis"))
        #expect(record.confirmedSpeciesId == (newestIsClear ? nil : VerifiedReviewFixtures.speciesID))
        #expect(record.userReviewState == (newestIsClear ? .unreviewed : .userOverridden))
        #expect(!record.userConfirmedIdentification)
    }

    @Test func competingHistoryAndAcknowledgementsCannotRegressTheRevision() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        try await HistoricalDatabaseActor(modelContainer: context.container).reconcileScanPage(
            responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history())])
        let jobs = try (1...20).map { revision in
            let payload = VerifiedReviewFixtures.review(revision, name: revision.isMultiple(of: 2) ? nil : "Examplea testus")
            return (try VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(payload)), try VerifiedReviewFixtures.decode(payload))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (row, review) in jobs {
                group.addTask {
                    if review.revision.isMultiple(of: 2) {
                        _ = try await BackgroundDatabaseActor(modelContainer: context.container).applyVerifiedSpeciesReview(
                            scanID: VerifiedReviewFixtures.scanID, review: review, acknowledging: nil)
                    } else {
                        try await HistoricalDatabaseActor(modelContainer: context.container).reconcileScanPage(responses: [row])
                    }
                }
            }
            try await group.waitForAll()
        }
        let record = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(record.confirmedSpeciesReview?.revision == 20 && record.confirmedSpeciesReview?.identity == nil)
        #expect(record.confirmedSpeciesId == nil && record.userIdentificationOverride == nil && record.userReviewState == .unreviewed)
    }


    @Test func diskReopeningPreservesVerifiedReplacementAndExplicitClear() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("verified-review-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.sqlite")
        let schema = Schema(versionedSchema: CurrentSchema.self)
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        }
        do {
            let container = try open()
            try await HistoricalDatabaseActor(modelContainer: container).reconcileScanPage(responses: [
                VerifiedReviewFixtures.row(VerifiedReviewFixtures.history(VerifiedReviewFixtures.review(2, name: "Examplea altera")))])
        }
        do {
            let container = try open(); let context = ModelContext(container)
            let record = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            #expect(record.verifiedConfirmedSpeciesIdentity?.scientificName == "Examplea altera")
            let clear = try VerifiedReviewFixtures.decode(VerifiedReviewFixtures.review(3, name: nil))
            _ = try await BackgroundDatabaseActor(modelContainer: container).applyVerifiedSpeciesReview(
                scanID: VerifiedReviewFixtures.scanID, review: clear, acknowledging: nil)
        }
        let reopened = try open(); let context = ModelContext(reopened)
        let record = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(record.confirmedSpeciesReview?.revision == 3 && record.confirmedSpeciesReview?.identity == nil)
        #expect(record.confirmedSpeciesIdentityData != nil && record.confirmedSpeciesId == nil)
        #expect(record.scientificName == "Examplea" && record.confidenceScore == 0.42)
    }

}
