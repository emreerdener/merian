import Foundation
import SwiftData

/// The only native writer of verified confirmation bytes. Legacy review fields
/// may hold pending local intent; original AI fields never change here.
enum ConfirmedSpeciesReviewPersistence {
    // One bounded process gate coordinates distinct ModelActors. No suspension
    // is allowed while held. Every transaction fetches in a fresh ModelContext.
    private static let mergeLock = NSLock()

    static func transaction<Value>(_ operation: () throws -> Value) rethrows -> Value {
        mergeLock.lock()
        defer { mergeLock.unlock() }
        return try operation()
    }

    static func validateMerge(_ incoming: ConfirmedSpeciesReview?, into record: LocalScanRecord) throws {
        _ = try ConfirmedSpeciesReview.merging(
            stored: ConfirmedSpeciesReview.restoring(record.confirmedSpeciesIdentityData), incoming: incoming)
    }

    @discardableResult
    static func merge(_ incoming: ConfirmedSpeciesReview?, into record: LocalScanRecord,
                      acknowledging intent: InferenceIdentificationReviewMutation? = nil) throws -> Bool {
        let current = try ConfirmedSpeciesReview.restoring(record.confirmedSpeciesIdentityData)
        let merged = try ConfirmedSpeciesReview.merging(stored: current, incoming: incoming)
        guard let incoming, merged == incoming else { return false }
        let acknowledgesCurrentIntent = intent.map {
            record.userIdentificationOverride == $0.override &&
                record.userConfirmedIdentification == $0.confirmed && record.userReviewState == $0.userReviewState
        } ?? false
        let newer = current == nil || incoming.revision > (current?.revision ?? 0)
        // An equal-revision history page must not erase unsent local intent.
        guard newer || acknowledgesCurrentIntent else { return false }
        record.confirmedSpeciesIdentityData = try incoming.storedData()
        if intent == nil || acknowledgesCurrentIntent {
            record.userIdentificationOverride = incoming.userIdentificationOverride
            record.userConfirmedIdentification = incoming.userConfirmedIdentification
            record.confirmedSpeciesId = incoming.confirmedSpeciesID
            record.userReviewState = incoming.userReviewState
        }
        return true
    }
}

extension BackgroundDatabaseActor {
    /// Called inside the existing serialized review write before remote work.
    /// A failed local save cannot send a confirmation or synthesize authority.
    func prepareVerifiedSpeciesReview(_ mutation: InferenceIdentificationReviewMutation,
                                      expectedReview: LocalAIIdentificationReview? = nil) throws -> VerifiedSpeciesReviewRequest {
        try withReviewRecord(mutation.scanID) { record, context in
            guard expectedReview == nil || record.localAIIdentificationReview == expectedReview else {
                throw ConfirmedSpeciesReview.IntegrityError.conflictingRevision
            }
            guard let primary = record.primaryIdentification, primary.value != nil else {
                throw ConfirmedSpeciesReview.IntegrityError.invalidRequest
            }
            let review = try ConfirmedSpeciesReview.restoring(record.confirmedSpeciesIdentityData)
            let request = try VerifiedSpeciesReviewRequest(mutation: mutation, revision: review?.revision ?? 0, primary: primary)
            record.userIdentificationOverride = mutation.override
            record.userConfirmedIdentification = mutation.confirmed
            record.confirmedSpeciesId = nil
            record.userReviewState = mutation.userReviewState
            try context.save()
            return request
        }
    }

    func applyVerifiedSpeciesReview(
        scanID: String, review: ConfirmedSpeciesReview,
        acknowledging intent: InferenceIdentificationReviewMutation?
    ) throws -> ConfirmedSpeciesReview? {
        try withReviewRecord(scanID) { record, context in
            guard record.primaryIdentification?.value != nil else {
                throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
            }
            if try ConfirmedSpeciesReviewPersistence.merge(review, into: record, acknowledging: intent) {
                try context.save()
            }
            let current = try ConfirmedSpeciesReview.restoring(record.confirmedSpeciesIdentityData)
            return current?.matchesIntent(override: record.userIdentificationOverride,
                confirmed: record.userConfirmedIdentification, state: record.userReviewState) == true ? current : nil
        }
    }

    private func withReviewRecord<Value>(_ scanID: String, _ operation: (LocalScanRecord, ModelContext) throws -> Value) throws -> Value {
        try ConfirmedSpeciesReviewPersistence.transaction {
            // A fresh context prevents a prior actor fetch from hiding another
            // writer's newer revision after it releases the transaction gate.
            let context = ModelContext(modelContainer)
            do {
                try Task.checkCancellation()
                guard try !ObservationHistoryEnrollmentIntent.protects(scanID, context: context) else {
                    throw ConfirmedSpeciesReview.IntegrityError.invalidRequest
                }
                var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanID })
                descriptor.fetchLimit = 1
                guard let record = try context.fetch(descriptor).first else {
                    throw ConfirmedSpeciesReview.IntegrityError.missingRecord
                }
                return try operation(record, context)
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}

extension LocalScanRecord {
    var confirmedSpeciesReview: ConfirmedSpeciesReview? {
        guard primaryIdentification?.value != nil else { return nil }
        return try? ConfirmedSpeciesReview.restoring(confirmedSpeciesIdentityData)
    }

    /// Species totals can use a verified selection while the original AI rank stays unchanged.
    var effectiveSpeciesNameForStatistics: String? {
        if localAIIdentificationReview.isUnresolved { return nil }
        if let community = localAIIdentificationReview.community { return community.rank == "species" ? community.scientific_name : nil }
        if primaryIdentification != nil {
            guard primaryIdentification?.value != nil,
                  confirmedSpeciesIdentityData == nil || confirmedSpeciesReview != nil else { return nil }
            if let selected = verifiedConfirmedSpeciesIdentity { return selected.scientificName }
        }
        return hasSpeciesLevelIdentification ? scientificName : nil
    }

    /// A pending local change cannot borrow the previous selection's authority.
    var verifiedConfirmedSpeciesIdentity: ConfirmedSpeciesReview.Identity? {
        guard !localAIIdentificationReview.isUnresolved, localAIIdentificationReview.community == nil else { return nil }
        guard let review = confirmedSpeciesReview,
              review.matchesIntent(override: userIdentificationOverride,
                                   confirmed: userConfirmedIdentification, state: userReviewState) else { return nil }
        return review.identity
    }
}
