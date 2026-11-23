import Foundation

/// Native evidence admission retains one identity and frozen context across
/// uncertain writer acknowledgements, independently of legacy media copying.
extension OfflineQueueManager {
    /// A retained context may replay an uncertain native acceptance, including
    /// a queue row whose save acknowledgement was lost. It cannot enter either
    /// legacy enqueue path or claim a second funding reservation.
    func beginNativeCaptureAdmission(
        plan: CaptureInitialEvidencePlan,
        retained: SharedMediaCaptureSubmissionContext?,
        makeContext: (CaptureInitialEvidencePlan, ScanFundingReservation) throws -> SharedMediaCaptureSubmissionContext
    ) throws -> SharedMediaCaptureSubmissionContext {
        let scanID = plan.scanID.uuidString.lowercased()
        guard captureLibraryAdmission(plan.ownerID), !inFlightInitialCaptureIDs.contains(scanID) else {
            throw SharedMediaStorageFailure.closed
        }
        if let retained {
            try retained.validate(plan: plan)
            inFlightInitialCaptureIDs.insert(scanID)
            return retained
        }
        guard beginInitialCaptureAdmission(scanID) else { throw SharedMediaStorageFailure.conflict }
        var funding: ScanFundingReservation?
        do {
            var images = 0, audio = 0, descriptions = 0, videos = 0
            for item in plan.items {
                switch item {
                case .image: images += 1
                case .audio: audio += 1
                case .description: descriptions += 1
                case .video: videos += 1
                }
            }
            guard let claimed = CaptureFundingAdmission.claimFundingAdmission(scanId: scanID,
                flashFallbackEligible: IdentificationEvidenceAllowance.permitsFreeScan(
                    images: images, audio: audio, descriptions: descriptions, videos: videos),
                consumeLocalMeter: false) else {
                throw SharedMediaStorageFailure.closed
            }
            funding = claimed
            let context = try makeContext(plan, claimed)
            try context.validate(plan: plan)
            guard try context.metadata(plan: plan).funding == claimed else { throw SharedMediaStorageFailure.conflict }
            return context
        } catch {
            // No native writer has been invoked. Only this pre-write failure
            // proves local rollback is safe; acceptance errors retain funding.
            if let funding { CaptureFundingAdmission.rollbackFundingAdmission(funding) }
            inFlightInitialCaptureIDs.remove(scanID)
            throw error
        }
    }

    func endNativeCaptureAdmission(scanID: UUID) {
        inFlightInitialCaptureIDs.remove(scanID.uuidString.lowercased())
    }

}
