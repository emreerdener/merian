enum CaptureSubmissionPolicy {
    nonisolated static func isImageImportFlashFallbackEligible(
        existingItemCount: Int,
        prospectiveImageCount: Int,
        isRefining: Bool
    ) -> Bool {
        !isRefining && existingItemCount == 0 && prospectiveImageCount == 1
    }

    nonisolated static func isFlashFallbackEligible(
        _ timeline: [CaptureSubmissionMediaItem],
        targetEradicationScanId: String? = nil
    ) -> Bool {
        guard targetEradicationScanId == nil, timeline.count == 1 else {
            return false
        }
        switch timeline[0] {
        case .image, .audio, .description:
            return true
        case .video:
            return false
        }
    }

    nonisolated static func shouldOptimizeLiveImageAnalysis(
        hasStillImage: Bool,
        hasAudio: Bool,
        hasVideo: Bool,
        isGalleryPhoto: Bool
    ) -> Bool {
        hasStillImage && !hasAudio && !hasVideo && !isGalleryPhoto
    }

    nonisolated static func preferredGoal(
        _ preferredGoal: FieldTripPreferredGoal?,
        hasCameraStill: Bool,
        hasGalleryStill: Bool,
        hasAudio: Bool,
        hasVideo: Bool
    ) -> FieldTripPreferredGoal? {
        guard hasCameraStill,
              !hasGalleryStill,
              !hasAudio,
              !hasVideo else {
            return nil
        }
        return preferredGoal
    }
}
