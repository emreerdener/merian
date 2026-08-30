import Testing

@testable import Merian

@Suite("Capture submission policies")
struct CaptureSubmissionPolicyTests {
    @Test func admissionResolutionFailsClosedAndUsesQueueOnlyFallback() {
        let allowed = ScanAdmissionPreview(
            decision: .allowed,
            effectivePlan: "free",
            dailyLimit: 3,
            dailyRemaining: 2
        )
        let exhausted = ScanAdmissionPreview(
            decision: .dailyQuotaExhausted,
            effectivePlan: "free",
            dailyLimit: 1,
            dailyRemaining: 0
        )

        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: false,
            previewResult: .available(allowed)
        ) == .proceed(.foreground))
        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: true,
            previewResult: .available(exhausted)
        ) == .paywall)
        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: false,
            canStartLocally: true,
            previewResult: nil
        ) == .proceed(.queued))
        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: true,
            previewResult: .connectivityUnavailable
        ) == .proceed(.queued))
        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: false,
            previewResult: .connectivityUnavailable
        ) == .paywall)
        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: true,
            previewResult: .unavailable
        ) == .retryRequired)
    }

    @Test func flashFallbackMatchesServerEvidenceShape() {
        #expect(CaptureSubmissionPolicy.isFlashFallbackEligible([
            .image(index: 0)
        ]))
        #expect(CaptureSubmissionPolicy.isFlashFallbackEligible([
            .audio("recording.wav")
        ]))
        #expect(CaptureSubmissionPolicy.isFlashFallbackEligible([
            .description(ObservationContext(freeText: "Yellow wings"))
        ]))
        #expect(!CaptureSubmissionPolicy.isFlashFallbackEligible([
            .video("clip.mp4")
        ]))
        #expect(!CaptureSubmissionPolicy.isFlashFallbackEligible([
            .image(index: 0),
            .description(ObservationContext(freeText: "Nearby leaves"))
        ]))
        #expect(!CaptureSubmissionPolicy.isFlashFallbackEligible(
            [.image(index: 0)],
            targetEradicationScanId: "prior-scan"
        ))
    }

    @Test func imageImportFallbackRequiresOneOrdinaryEmptyWorkspaceSlot() {
        #expect(CaptureSubmissionPolicy.isImageImportFlashFallbackEligible(
            existingItemCount: 0,
            prospectiveImageCount: 1,
            isRefining: false
        ))
        #expect(!CaptureSubmissionPolicy.isImageImportFlashFallbackEligible(
            existingItemCount: 0,
            prospectiveImageCount: 2,
            isRefining: false
        ))
        #expect(!CaptureSubmissionPolicy.isImageImportFlashFallbackEligible(
            existingItemCount: 1,
            prospectiveImageCount: 1,
            isRefining: false
        ))
        #expect(!CaptureSubmissionPolicy.isImageImportFlashFallbackEligible(
            existingItemCount: 0,
            prospectiveImageCount: 1,
            isRefining: true
        ))
    }

    @Test func liveImageLatencyOptimizationExcludesGalleryAudioAndVideo() {
        #expect(CaptureSubmissionPolicy.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: false,
            hasVideo: false,
            isGalleryPhoto: false
        ))
        #expect(!CaptureSubmissionPolicy.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: false,
            hasVideo: false,
            isGalleryPhoto: true
        ))
        #expect(!CaptureSubmissionPolicy.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: true,
            hasVideo: false,
            isGalleryPhoto: false
        ))
        #expect(!CaptureSubmissionPolicy.shouldOptimizeLiveImageAnalysis(
            hasStillImage: false,
            hasAudio: false,
            hasVideo: true,
            isGalleryPhoto: false
        ))
    }

    @Test func preferredGoalRequiresCameraOnlyStillMedia() {
        let preferredGoal = FieldTripPreferredGoal(
            userFieldTripId: "outing",
            itemId: "butterfly"
        )

        #expect(CaptureSubmissionPolicy.preferredGoal(
            preferredGoal,
            hasCameraStill: true,
            hasGalleryStill: false,
            hasAudio: false,
            hasVideo: false
        ) == preferredGoal)
        #expect(CaptureSubmissionPolicy.preferredGoal(
            preferredGoal,
            hasCameraStill: true,
            hasGalleryStill: true,
            hasAudio: false,
            hasVideo: false
        ) == nil)
        #expect(CaptureSubmissionPolicy.preferredGoal(
            preferredGoal,
            hasCameraStill: true,
            hasGalleryStill: false,
            hasAudio: true,
            hasVideo: false
        ) == nil)
        #expect(CaptureSubmissionPolicy.preferredGoal(
            preferredGoal,
            hasCameraStill: false,
            hasGalleryStill: false,
            hasAudio: false,
            hasVideo: true
        ) == nil)
    }
}
