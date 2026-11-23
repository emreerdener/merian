import Foundation

/// Shared initial-Capture funding admission. Only proven pre-persistence
/// failures refund the local meter; uncertain native writes retain admission.
@MainActor
enum CaptureFundingAdmission {
    static func claimFundingAdmission(
        scanId: String,
        timeline: [CaptureSubmissionMediaItem]
    ) -> ScanFundingReservation? {
        claimFundingAdmission(scanId: scanId, flashFallbackEligible: isFlashFallbackEligible(timeline))
    }

    static func claimFundingAdmission(
        scanId: String, flashFallbackEligible: Bool, consumeLocalMeter: Bool = true) -> ScanFundingReservation? {
        guard let funding = EntitlementManager.shared.claimFunding(
            scanId: scanId,
            flashFallbackEligible: flashFallbackEligible
        ) else {
            UsageManager.shared.showPaywall = true
            return nil
        }
        if funding.source == .immediateFlash ||
            funding.source == .deferredFlash {
            guard UsageManager.shared.canPerformScan(isProActive: false) else {
                EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
                    scanId: funding.scanId
                )
                UsageManager.shared.showPaywall = true
                return nil
            }
            // Native admission has not persisted its context yet. Only its
            // qualified accepted-work recovery may record the advisory meter.
            if consumeLocalMeter { UsageManager.shared.consumeScan(scanId: funding.scanId) }
        }
        return funding
    }

    static func rollbackFundingAdmission(_ funding: ScanFundingReservation) {
        if funding.source == .immediateFlash ||
            funding.source == .deferredFlash {
            UsageManager.shared.refundScan(scanId: funding.scanId)
        }
        EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
            scanId: funding.scanId
        )
    }

    private static func isFlashFallbackEligible(
        _ timeline: [CaptureSubmissionMediaItem]
    ) -> Bool {
        CaptureSubmissionPolicy.isFlashFallbackEligible(timeline)
    }

}
