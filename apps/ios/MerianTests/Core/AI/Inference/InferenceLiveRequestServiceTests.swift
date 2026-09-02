import Foundation
import Testing

@testable import Merian

private final class LockedRequestBodyFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    func mark() {
        lock.lock()
        storedValue = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

@MainActor
private final class LiveRequestDependencyRecorder {
    var encodedImages: [String] = []
    var uploadedVideoKeys: [String] = []
    var resultData = Data("response".utf8)
    var onEncode: () -> Void = {}
    var onUpload: () -> Void = {}
    var onIdentify: () -> Void = {}
    private(set) var encodedInputs: [[Data]] = []
    private(set) var uploadInputs: [([String], String)] = []
    private(set) var providerRequests:
        [InferenceLiveRequestService.ProviderRequest] = []
    private(set) var requestBodyCallbackWasPresent = false

    func dependencies() -> InferenceLiveRequestService.Dependencies {
        InferenceLiveRequestService.Dependencies(
            encodeVisualImages: { [self] images in
                encodedInputs.append(images)
                onEncode()
                return encodedImages
            },
            uploadStagedVideoFiles: { [self] paths, scanId in
                uploadInputs.append((paths, scanId))
                onUpload()
                return uploadedVideoKeys
            },
            identify: { [self] request, onRequestBodySent in
                providerRequests.append(request)
                requestBodyCallbackWasPresent = onRequestBodySent != nil
                onIdentify()
                onRequestBodySent?()
                return resultData
            }
        )
    }
}

@MainActor
private final class LiveRequestAttemptState {
    var isCurrent = true
    private(set) var validationCount = 0

    func validate() throws {
        validationCount += 1
        guard isCurrent else { throw CancellationError() }
    }
}

@MainActor
@Suite("Inference Live Request Service")
struct InferenceLiveRequestServiceTests {
    @Test func visualDispatchBuildsCanonicalProviderPayload() async throws {
        let recorder = LiveRequestDependencyRecorder()
        recorder.encodedImages = ["encoded-image", "encoded-frame"]
        recorder.uploadedVideoKeys = ["video-object-key"]
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )
        let attempt = LiveRequestAttemptState()
        let requestBodyFlag = LockedRequestBodyFlag()
        var providerDispatchReadyCount = 0
        let projection = makeProjection(
            observations: [ObservationContext(freeText: "striped wings")]
        )
        let visualItems: [IdentifyVisualMediaItem] = [
            .image(sourceIndex: 0),
            .videoFrame(clipIndex: 0, frameIndex: 0)
        ]
        let ownerTimeline: [IdentifyOwnerMediaTimelineItem] = [
            .image(sourceIndex: 0),
            .video(clipIndex: 0),
            .audio(audioInputIndex: 0, sourceIndex: 0),
            .description(contextIndex: 0)
        ]
        let preferredGoal = FieldTripPreferredGoal(
            userFieldTripId: "field-trip",
            itemId: "goal"
        )
        let images = [
            Data([0xFF, 0xD8, 0xFF, 0x00]),
            Data([0x52, 0x49, 0x46, 0x46])
        ]

        let response = try #require(
            await service.dispatchVisual(
                InferenceLiveRequestService.VisualRequest(
                    compressedImages: images,
                    submissionProjection: projection,
                    ownerMediaTimeline: ownerTimeline,
                    visualMediaItems: visualItems,
                    telemetry: makeTelemetry(),
                    clientScanId: "scan-id",
                    preferredGoal: preferredGoal,
                    durableQueueOwnsRecovery: true,
                    pipelineStartedAt: CFAbsoluteTimeGetCurrent()
                ),
                validateAttempt: { try attempt.validate() },
                onProviderDispatchReady: {
                    providerDispatchReadyCount += 1
                },
                onRequestBodySent: { requestBodyFlag.mark() }
            )
        )

        #expect(response.resultData == recorder.resultData)
        #expect(response.observationContextsJSON.count == 1)
        #expect(recorder.encodedInputs == [images])
        #expect(recorder.uploadInputs.count == 1)
        #expect(recorder.uploadInputs[0].0 == ["video.mov"])
        #expect(recorder.uploadInputs[0].1 == "scan-id")
        #expect(attempt.validationCount == 3)
        #expect(providerDispatchReadyCount == 1)
        #expect(requestBodyFlag.value)
        #expect(recorder.requestBodyCallbackWasPresent)

        let providerRequest = try #require(recorder.providerRequests.first)
        #expect(providerRequest.r2ObjectKeys.isEmpty)
        #expect(
            providerRequest.base64ImageDatas ==
                ["encoded-image", "encoded-frame"]
        )
        #expect(providerRequest.mimeType == "image/jpeg")
        #expect(providerRequest.audioFilePaths == ["audio.wav"])
        #expect(providerRequest.videoR2ObjectKeys == ["video-object-key"])
        #expect(providerRequest.videoFrameCount == 1)
        #expect(providerRequest.visualMediaItems == visualItems)
        #expect(providerRequest.audioMediaItems == projection.audioMediaItems)
        #expect(providerRequest.ownerMediaTimeline == ownerTimeline)
        #expect(providerRequest.clientScanId == "scan-id")
        #expect(providerRequest.preferredGoal == preferredGoal)
        #expect(providerRequest.durableQueueOwnsRecovery)
        #expect(
            try JSONDecoder().decode(
                ObservationContext.self,
                from: Data(
                    providerRequest.observationContextsJSON[0].utf8
                )
            ) == ObservationContext(freeText: "striped wings")
        )
    }

    @Test func visualDispatchDropsMisalignedDescriptors() async throws {
        let recorder = LiveRequestDependencyRecorder()
        recorder.encodedImages = ["one-image"]
        recorder.uploadedVideoKeys = ["video-object-key"]
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )
        let attempt = LiveRequestAttemptState()
        let images = [Data([0x00]), Data([0x01])]

        _ = try #require(
            await service.dispatchVisual(
                InferenceLiveRequestService.VisualRequest(
                    compressedImages: images,
                    submissionProjection: makeProjection(),
                    ownerMediaTimeline: nil,
                    visualMediaItems: [
                        .image(sourceIndex: 0),
                        .videoFrame(clipIndex: 0, frameIndex: 0)
                    ],
                    telemetry: makeTelemetry(),
                    clientScanId: "scan-id",
                    preferredGoal: nil,
                    durableQueueOwnsRecovery: false,
                    pipelineStartedAt: CFAbsoluteTimeGetCurrent()
                ),
                validateAttempt: { try attempt.validate() },
                onProviderDispatchReady: {},
                onRequestBodySent: {}
            )
        )

        let providerRequest = try #require(recorder.providerRequests.first)
        #expect(providerRequest.visualMediaItems == nil)
        #expect(providerRequest.videoFrameCount == images.count)
        #expect(providerRequest.mimeType == "image/webp")
        #expect(providerRequest.ownerMediaTimeline == nil)
    }

    @Test func emptyVisualEncodingNeverDispatchesProviderWork() async throws {
        let recorder = LiveRequestDependencyRecorder()
        recorder.encodedImages = [""]
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )
        let attempt = LiveRequestAttemptState()

        let response = try await service.dispatchVisual(
            InferenceLiveRequestService.VisualRequest(
                compressedImages: [Data([0x01])],
                submissionProjection: makeProjection(videoPaths: []),
                ownerMediaTimeline: nil,
                visualMediaItems: nil,
                telemetry: makeTelemetry(),
                clientScanId: "scan-id",
                preferredGoal: nil,
                durableQueueOwnsRecovery: true,
                pipelineStartedAt: CFAbsoluteTimeGetCurrent()
            ),
            validateAttempt: { try attempt.validate() },
            onProviderDispatchReady: {},
            onRequestBodySent: {}
        )

        #expect(response == nil)
        #expect(attempt.validationCount == 1)
        #expect(recorder.uploadInputs.isEmpty)
        #expect(recorder.providerRequests.isEmpty)
    }

    @Test func visualDispatchRevalidatesAfterVideoUpload() async throws {
        let recorder = LiveRequestDependencyRecorder()
        recorder.encodedImages = ["encoded-image"]
        recorder.uploadedVideoKeys = ["video-object-key"]
        let attempt = LiveRequestAttemptState()
        recorder.onUpload = { attempt.isCurrent = false }
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )
        var didCancel = false

        do {
            _ = try await service.dispatchVisual(
                InferenceLiveRequestService.VisualRequest(
                    compressedImages: [Data([0x01])],
                    submissionProjection: makeProjection(),
                    ownerMediaTimeline: nil,
                    visualMediaItems: [.image(sourceIndex: 0)],
                    telemetry: makeTelemetry(),
                    clientScanId: "scan-id",
                    preferredGoal: nil,
                    durableQueueOwnsRecovery: true,
                    pipelineStartedAt: CFAbsoluteTimeGetCurrent()
                ),
                validateAttempt: { try attempt.validate() },
                onProviderDispatchReady: {},
                onRequestBodySent: {}
            )
        } catch is CancellationError {
            didCancel = true
        }

        #expect(didCancel)
        #expect(attempt.validationCount == 2)
        #expect(recorder.uploadInputs.count == 1)
        #expect(recorder.providerRequests.isEmpty)
    }

    @Test func visualDispatchRevalidatesAfterImageEncoding() async throws {
        let recorder = LiveRequestDependencyRecorder()
        recorder.encodedImages = ["encoded-image"]
        let attempt = LiveRequestAttemptState()
        recorder.onEncode = { attempt.isCurrent = false }
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )
        var didCancel = false

        do {
            _ = try await service.dispatchVisual(
                InferenceLiveRequestService.VisualRequest(
                    compressedImages: [Data([0x01])],
                    submissionProjection: makeProjection(videoPaths: []),
                    ownerMediaTimeline: nil,
                    visualMediaItems: [.image(sourceIndex: 0)],
                    telemetry: makeTelemetry(),
                    clientScanId: "scan-id",
                    preferredGoal: nil,
                    durableQueueOwnsRecovery: true,
                    pipelineStartedAt: CFAbsoluteTimeGetCurrent()
                ),
                validateAttempt: { try attempt.validate() },
                onProviderDispatchReady: {},
                onRequestBodySent: {}
            )
        } catch is CancellationError {
            didCancel = true
        }

        #expect(didCancel)
        #expect(attempt.validationCount == 1)
        #expect(recorder.uploadInputs.isEmpty)
        #expect(recorder.providerRequests.isEmpty)
    }

    @Test func nonVisualDispatchBuildsAudioOnlyPayload() async throws {
        let recorder = LiveRequestDependencyRecorder()
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )
        let attempt = LiveRequestAttemptState()
        let projection = makeProjection(
            videoPaths: [],
            observations: [ObservationContext(freeText: "three notes")]
        )
        let ownerTimeline: [IdentifyOwnerMediaTimelineItem] = [
            .audio(audioInputIndex: 0, sourceIndex: 0),
            .description(contextIndex: 0)
        ]

        let response = try await service.dispatchNonVisual(
            InferenceLiveRequestService.NonVisualRequest(
                submissionProjection: projection,
                ownerMediaTimeline: ownerTimeline,
                telemetry: makeTelemetry(),
                clientScanId: nil,
                durableQueueOwnsRecovery: false
            ),
            validateAttempt: { try attempt.validate() }
        )

        #expect(response.resultData == recorder.resultData)
        #expect(attempt.validationCount == 2)
        #expect(recorder.encodedInputs.isEmpty)
        #expect(recorder.uploadInputs.isEmpty)
        let providerRequest = try #require(recorder.providerRequests.first)
        #expect(providerRequest.r2ObjectKeys.isEmpty)
        #expect(providerRequest.base64ImageDatas.isEmpty)
        #expect(providerRequest.mimeType == "image/webp")
        #expect(providerRequest.audioFilePaths == ["audio.wav"])
        #expect(providerRequest.videoR2ObjectKeys.isEmpty)
        #expect(providerRequest.videoFrameCount == nil)
        #expect(providerRequest.visualMediaItems == nil)
        #expect(providerRequest.audioMediaItems == projection.audioMediaItems)
        #expect(providerRequest.ownerMediaTimeline == ownerTimeline)
        #expect(providerRequest.clientScanId == nil)
        #expect(providerRequest.preferredGoal == nil)
        #expect(!providerRequest.durableQueueOwnsRecovery)
        #expect(!recorder.requestBodyCallbackWasPresent)
    }

    @Test func nonVisualDispatchRevalidatesAfterProviderReturn() async throws {
        let recorder = LiveRequestDependencyRecorder()
        let attempt = LiveRequestAttemptState()
        recorder.onIdentify = { attempt.isCurrent = false }
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )
        var didCancel = false

        do {
            _ = try await service.dispatchNonVisual(
                InferenceLiveRequestService.NonVisualRequest(
                    submissionProjection: makeProjection(videoPaths: []),
                    ownerMediaTimeline: nil,
                    telemetry: makeTelemetry(),
                    clientScanId: "scan-id",
                    durableQueueOwnsRecovery: true
                ),
                validateAttempt: { try attempt.validate() }
            )
        } catch is CancellationError {
            didCancel = true
        }

        #expect(didCancel)
        #expect(attempt.validationCount == 2)
        #expect(recorder.providerRequests.count == 1)
    }

    @Test func visualDispatchRequiresJPEGMagicBytesForJPEGMIME() async throws {
        #expect(
            try await dispatchedMIMEType(
                for: [Data([0xFF, 0xD8, 0xFF])]
            ) == "image/jpeg"
        )
        #expect(
            try await dispatchedMIMEType(
                for: [Data([0xFF, 0xD8])]
            ) == "image/webp"
        )
        #expect(
            try await dispatchedMIMEType(for: []) == "image/webp"
        )
    }

    private func dispatchedMIMEType(for images: [Data]) async throws -> String {
        let recorder = LiveRequestDependencyRecorder()
        recorder.encodedImages = ["encoded-image"]
        let service = InferenceLiveRequestService(
            dependencies: recorder.dependencies()
        )

        _ = try #require(
            await service.dispatchVisual(
                InferenceLiveRequestService.VisualRequest(
                    compressedImages: images,
                    submissionProjection: makeProjection(videoPaths: []),
                    ownerMediaTimeline: nil,
                    visualMediaItems: nil,
                    telemetry: makeTelemetry(),
                    clientScanId: "scan-id",
                    preferredGoal: nil,
                    durableQueueOwnsRecovery: false,
                    pipelineStartedAt: CFAbsoluteTimeGetCurrent()
                ),
                validateAttempt: {},
                onProviderDispatchReady: {},
                onRequestBodySent: {}
            )
        )

        let providerRequest = try #require(recorder.providerRequests.first)
        return providerRequest.mimeType
    }

    private func makeProjection(
        videoPaths: [String] = ["video.mov"],
        observations: [ObservationContext] = []
    ) -> CaptureSubmissionMediaProjection {
        CaptureSubmissionMediaProjection(
            audioFilePaths: ["audio.wav"],
            audioMediaItems: [.audio(sourceIndex: 0)],
            videoFilePaths: videoPaths,
            observationContexts: observations,
            ownerMediaTimeline: []
        )
    }

    private func makeTelemetry() -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: 1.5,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: "Test Habitat",
            weatherCondition: "clear",
            weatherTemperatureF: 70,
            timeOfDay: "day",
            timestamp: "2026-09-01T12:00:00Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }
}
