import Foundation

extension InferenceLiveQueueService {
    static let live = Self(
        dependencies: .init(
            releaseDeferredUpload: { scanId, foregroundGeneration, reason in
                OfflineQueueManager.shared.releaseDeferredLiveUpload(
                    scanId: scanId,
                    foregroundInferenceGeneration: foregroundGeneration,
                    reason: reason
                )
            },
            retireForegroundInference: { scanId, generation, resumeBackground, reason in
                OfflineQueueManager.shared.retireForegroundInference(
                    scanId: scanId,
                    generation: generation,
                    resumeBackground: resumeBackground,
                    reason: reason
                )
            },
            claimForegroundInferenceStart: { scanId, generation in
                OfflineQueueManager.shared.claimForegroundInferenceStart(
                    scanId: scanId,
                    generation: generation
                )
            },
            isForegroundInferenceAttemptCurrent: { scanId, generation in
                OfflineQueueManager.shared
                    .isForegroundInferenceAttemptCurrent(
                        scanId: scanId,
                        generation: generation
                    )
            },
            foregroundInferenceGeneration: { scanId in
                OfflineQueueManager.shared
                    .foregroundInferenceGenerations[scanId]
            },
            deleteQueuedScan: { scanId, mediaPaths, generation in
                await OfflineQueueManager.shared.deleteQueuedScan(
                    scanId: scanId,
                    explicitlyAdoptedMediaPaths: mediaPaths,
                    preservePreferredGoalHint: true,
                    foregroundInferenceExpectation:
                        ForegroundInferenceGenerationExpectation(
                            generation: generation
                        )
                )
            },
            rejectQueuedScan: { scanId, reason, errorCode in
                OfflineQueueManager.shared.softDeleteQueuedScan(
                    scanId: scanId,
                    reason: reason,
                    errorCode: errorCode,
                    httpStatus: 400,
                    needsAttention: false
                )
            }
        )
    )
}
