import Foundation
import Testing

@testable import Merian

@MainActor
private final class InferenceLiveQueueRecorder {
    enum Event: Equatable {
        case released(String, UUID?, String)
        case retired(String, UUID, Bool, String)
        case claimed(String, UUID)
        case checked(String, UUID)
        case generationRead(String)
        case deleted(String, [String], UUID)
        case rejected(String, String, String)
    }

    var claimResult = true
    var currentResult = true
    var deleteResult = true
    var rejectResult = true
    var generations: [String: UUID] = [:]
    private(set) var events: [Event] = []

    var service: InferenceLiveQueueService {
        InferenceLiveQueueService(dependencies: .init(
            releaseDeferredUpload: { [self] scanId, generation, reason in
                events.append(.released(scanId, generation, reason))
            },
            retireForegroundInference: { [self] scanId, generation, resumeBackground, reason in
                events.append(
                    .retired(scanId, generation, resumeBackground, reason)
                )
            },
            claimForegroundInferenceStart: { [self] scanId, generation in
                events.append(.claimed(scanId, generation))
                return claimResult
            },
            isForegroundInferenceAttemptCurrent: { [self] scanId, generation in
                events.append(.checked(scanId, generation))
                return currentResult
            },
            foregroundInferenceGeneration: { [self] scanId in
                events.append(.generationRead(scanId))
                return generations[scanId]
            },
            deleteQueuedScan: { [self] scanId, mediaPaths, generation in
                events.append(.deleted(scanId, mediaPaths, generation))
                return deleteResult
            },
            rejectQueuedScan: { [self] scanId, reason, errorCode in
                events.append(.rejected(scanId, reason, errorCode))
                return rejectResult
            }
        ))
    }
}

@MainActor
@Suite("Inference Live Queue Service")
struct InferenceLiveQueueServiceTests {
    @Test func forwardsAdmissionOwnershipAndLifecycleValuesExactly() {
        let recorder = InferenceLiveQueueRecorder()
        let service = recorder.service
        let generation = UUID()

        service.releaseDeferredUpload(
            scanId: "scan-a",
            foregroundGeneration: generation,
            reason: "request_body_sent"
        )
        service.retireForegroundInference(
            scanId: "scan-a",
            generation: generation,
            resumeBackground: false,
            reason: "terminal"
        )
        #expect(
            service.claimForegroundInferenceStart(
                scanId: "scan-a",
                generation: generation
            )
        )
        #expect(
            service.isForegroundInferenceAttemptCurrent(
                scanId: "scan-a",
                generation: generation
            )
        )

        #expect(recorder.events == [
            .released("scan-a", generation, "request_body_sent"),
            .retired("scan-a", generation, false, "terminal"),
            .claimed("scan-a", generation),
            .checked("scan-a", generation)
        ])
    }

    @Test func preservesOptionalGenerationForQueueLessUploadRelease() {
        let recorder = InferenceLiveQueueRecorder()

        recorder.service.releaseDeferredUpload(
            scanId: "generated-client-id",
            foregroundGeneration: nil,
            reason: "inline_failsafe"
        )

        #expect(recorder.events == [
            .released("generated-client-id", nil, "inline_failsafe")
        ])
    }

    @Test func forwardsGenerationLookupDeletionAndRejection() async {
        let recorder = InferenceLiveQueueRecorder()
        let service = recorder.service
        let generation = UUID()
        recorder.generations["scan-a"] = generation

        #expect(
            service.foregroundInferenceGeneration(for: "scan-a")
                == generation
        )
        #expect(
            await service.deleteQueuedScan(
                scanId: "scan-a",
                explicitlyAdoptedMediaPaths: ["image.jpg", "audio.m4a"],
                foregroundGeneration: generation
            )
        )
        #expect(
            service.rejectQueuedScan(
                scanId: "scan-a",
                reason: "not identifiable",
                errorCode: "observation_rejected"
            )
        )

        #expect(recorder.events == [
            .generationRead("scan-a"),
            .deleted(
                "scan-a",
                ["image.jpg", "audio.m4a"],
                generation
            ),
            .rejected(
                "scan-a",
                "not identifiable",
                "observation_rejected"
            )
        ])
    }

    @Test func returnsDependencyDecisionsWithoutFallbackDefaults() async {
        let recorder = InferenceLiveQueueRecorder()
        let service = recorder.service
        let generation = UUID()
        recorder.claimResult = false
        recorder.currentResult = false
        recorder.deleteResult = false
        recorder.rejectResult = false

        #expect(
            !service.claimForegroundInferenceStart(
                scanId: "scan-a",
                generation: generation
            )
        )
        #expect(
            !service.isForegroundInferenceAttemptCurrent(
                scanId: "scan-a",
                generation: generation
            )
        )
        #expect(
            await service.deleteQueuedScan(
                scanId: "scan-a",
                explicitlyAdoptedMediaPaths: [],
                foregroundGeneration: generation
            ) == false
        )
        #expect(
            !service.rejectQueuedScan(
                scanId: "scan-a",
                reason: "reason",
                errorCode: "code"
            )
        )
    }
}
