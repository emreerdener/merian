enum CaptureSubmissionPolicy {
    nonisolated static func isFlashFallbackEligible(
        _ timeline: [CaptureSubmissionMediaItem],
        targetEradicationScanId: String? = nil
    ) -> Bool {
        guard targetEradicationScanId == nil else { return false }
        var images = 0, audio = 0, descriptions = 0, videos = 0
        for item in timeline {
            switch item {
            case .image: images += 1
            case .audio: audio += 1
            case .description(let context): descriptions += context.isEmpty ? 0 : 1
            case .video: videos += 1
            }
        }
        return IdentificationEvidenceAllowance.permitsFreeScan(
            images: images, audio: audio, descriptions: descriptions, videos: videos
        )
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
