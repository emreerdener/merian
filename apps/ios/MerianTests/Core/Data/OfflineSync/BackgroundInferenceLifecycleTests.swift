import Foundation
@testable import Merian
import Testing

@Suite(
    "Background Inference Lifecycle",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct BackgroundInferenceLifecycleTests {
    @Test func generationClaimIsExactAndIdempotent() {
        let manager = OfflineQueueManager.shared
        let scanId = "inference-generation-claim-\(UUID().uuidString)"
        let generation = UUID()
        let staleGeneration = UUID()
        reset(manager, scanId: scanId, generations: [
            generation,
            staleGeneration
        ])
        defer {
            reset(manager, scanId: scanId, generations: [
                generation,
                staleGeneration
            ])
        }

        #expect(manager.claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: generation
        ) == generation)
        #expect(manager.claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: generation
        ) == generation)
        #expect(manager.claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: staleGeneration
        ) == nil)
        #expect(manager.isInferenceGenerationCurrent(
            scanId: scanId,
            expectedGeneration: generation
        ))
        #expect(SyncStateManager.shared.phase == .inferencing)
    }

    @Test func retiredGenerationCannotBeReadopted() {
        let manager = OfflineQueueManager.shared
        let scanId = "retired-inference-generation-\(UUID().uuidString)"
        let generation = UUID()
        reset(manager, scanId: scanId, generations: [generation])
        manager.retiredInferenceGenerations.insert(generation)
        defer {
            reset(manager, scanId: scanId, generations: [generation])
        }

        #expect(manager.claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: generation
        ) == nil)
        #expect(manager.activeInferenceGenerations[scanId] == nil)
        #expect(SyncStateManager.shared.phase == .idle)
    }

    @Test func nilLegacyGenerationClaimsANewExactOwner() {
        let manager = OfflineQueueManager.shared
        let scanId = "legacy-inference-generation-\(UUID().uuidString)"
        reset(manager, scanId: scanId, generations: [])
        defer {
            if let generation = manager.activeInferenceGenerations[scanId] {
                manager.retiredInferenceGenerations.remove(generation)
            }
            reset(manager, scanId: scanId, generations: [])
        }

        let claimed = manager.claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: nil
        )

        #expect(claimed != nil)
        #expect(manager.activeInferenceGenerations[scanId] == claimed)
        #expect(SyncStateManager.shared.phase == .inferencing)
    }

    @Test func staleCompletionCannotClearReplacementGeneration() {
        let manager = OfflineQueueManager.shared
        let scanId = "inference-generation-completion-\(UUID().uuidString)"
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        let dispatchDate = Date(timeIntervalSince1970: 1_700_000_000)
        reset(manager, scanId: scanId, generations: [
            staleGeneration,
            currentGeneration
        ])
        defer {
            reset(manager, scanId: scanId, generations: [
                staleGeneration,
                currentGeneration
            ])
        }

        manager.activeInferenceGenerations[scanId] = currentGeneration
        manager.inferenceDispatchDates[scanId] = dispatchDate
        SyncStateManager.shared.beginInferencing(
            generation: staleGeneration
        )
        SyncStateManager.shared.beginInferencing(
            generation: currentGeneration
        )
        manager.inferenceStatusProbeTasks.replace(
            for: scanId,
            ownerGeneration: currentGeneration
        ) { _ in
            Task {
                try? await Task.sleep(for: .seconds(30))
            }
        }

        manager.finishInferenceGeneration(
            scanId: scanId,
            generation: staleGeneration
        )

        #expect(
            manager.activeInferenceGenerations[scanId]
                == currentGeneration
        )
        #expect(manager.inferenceDispatchDates[scanId] == dispatchDate)
        #expect(manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: currentGeneration
        ))
        #expect(SyncStateManager.shared.phase == .inferencing)

        manager.finishInferenceGeneration(
            scanId: scanId,
            generation: currentGeneration
        )

        #expect(manager.activeInferenceGenerations[scanId] == nil)
        #expect(manager.inferenceDispatchDates[scanId] == nil)
        #expect(!manager.inferenceStatusProbeTasks.isOwned(
            scanId,
            by: currentGeneration
        ))
        #expect(manager.retiredInferenceGenerations.contains(
            staleGeneration
        ))
        #expect(manager.retiredInferenceGenerations.contains(
            currentGeneration
        ))
        #expect(SyncStateManager.shared.phase == .idle)
    }

    private func reset(
        _ manager: OfflineQueueManager,
        scanId: String,
        generations: [UUID]
    ) {
        manager.inferenceStatusProbeTasks.cancel(scanId)
        manager.activeInferenceGenerations[scanId] = nil
        manager.inferenceDispatchDates[scanId] = nil
        for generation in generations {
            manager.retiredInferenceGenerations.remove(generation)
        }
        SyncStateManager.shared.forceIdle()
    }
}
