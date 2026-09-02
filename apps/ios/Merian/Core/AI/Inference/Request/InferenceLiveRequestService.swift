import Foundation

/// Prepares and dispatches the provider request for one live inference attempt.
///
/// Presentation identity, durable queue ownership, and recovery remain owned by
/// `InferenceEngine`; `InferenceLiveResultService` adapts response parsing and
/// persistence. The engine supplies an exact attempt validator around each
/// suspension point that could otherwise dispatch stale work.
struct InferenceLiveRequestService {
    struct Dependencies {
        let encodeVisualImages: @MainActor ([Data]) async -> [String]
        let uploadStagedVideoFiles:
            @MainActor (_ videoFilePaths: [String], _ scanId: String) async throws
                -> [String]
        let identify:
            @MainActor (_ request: ProviderRequest,
                        _ onRequestBodySent: (@Sendable () -> Void)?) async throws
                -> Data
    }

    struct ProviderRequest: Sendable {
        let r2ObjectKeys: [String]
        let base64ImageDatas: [String]
        let mimeType: String
        let audioFilePaths: [String]
        let videoR2ObjectKeys: [String]
        let videoFrameCount: Int?
        let visualMediaItems: [IdentifyVisualMediaItem]?
        let audioMediaItems: [IdentifyAudioMediaItem]?
        let ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]?
        let observationContextsJSON: [String]
        let telemetry: CaptureTelemetry
        let clientScanId: String?
        let preferredGoal: FieldTripPreferredGoal?
        let durableQueueOwnsRecovery: Bool
    }

    struct VisualRequest: Sendable {
        let compressedImages: [Data]
        let submissionProjection: CaptureSubmissionMediaProjection
        let ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]?
        let visualMediaItems: [IdentifyVisualMediaItem]?
        let telemetry: CaptureTelemetry
        let clientScanId: String
        let preferredGoal: FieldTripPreferredGoal?
        let durableQueueOwnsRecovery: Bool
        let pipelineStartedAt: CFAbsoluteTime
    }

    struct NonVisualRequest: Sendable {
        let submissionProjection: CaptureSubmissionMediaProjection
        let ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]?
        let telemetry: CaptureTelemetry
        let clientScanId: String?
        let durableQueueOwnsRecovery: Bool
    }

    struct Response: Sendable {
        let resultData: Data
        let observationContextsJSON: [String]
        let receivedAt: CFAbsoluteTime
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    static let live = InferenceLiveRequestService(
        dependencies: Dependencies(
            encodeVisualImages: { images in
                await InferenceProcessingActor.shared.encodeBase64(
                    compressedDatas: images
                )
            },
            uploadStagedVideoFiles: { videoFilePaths, scanId in
                try await MerianNetworkClient.shared.uploadStagedVideoFiles(
                    videoFilePaths: videoFilePaths,
                    scanId: scanId
                )
            },
            identify: { request, onRequestBodySent in
                try await MerianNetworkClient.shared.identifyMultiModal(
                    r2ObjectKeys: request.r2ObjectKeys,
                    base64ImageDatas: request.base64ImageDatas,
                    mimeType: request.mimeType,
                    audioFilePaths: request.audioFilePaths,
                    videoR2ObjectKeys: request.videoR2ObjectKeys,
                    videoFrameCount: request.videoFrameCount,
                    visualMediaItems: request.visualMediaItems,
                    audioMediaItems: request.audioMediaItems,
                    ownerMediaTimeline: request.ownerMediaTimeline,
                    observationContextsJSON: request.observationContextsJSON,
                    telemetry: request.telemetry,
                    clientScanId: request.clientScanId,
                    preferredGoal: request.preferredGoal,
                    durableQueueOwnsRecovery:
                        request.durableQueueOwnsRecovery,
                    onRequestBodySent: onRequestBodySent
                )
            }
        )
    )

    /// Returns `nil` only when every encoded image is empty. The engine retains
    /// the existing refund and durable-owner retirement policy for that case.
    @MainActor
    func dispatchVisual(
        _ request: VisualRequest,
        validateAttempt: @MainActor () throws -> Void,
        onProviderDispatchReady: @MainActor () -> Void,
        onRequestBodySent: @escaping @Sendable () -> Void
    ) async throws -> Response? {
        let encodedImages = await dependencies.encodeVisualImages(
            request.compressedImages
        )
        try validateAttempt()

        let validEncodedImages = encodedImages.filter { !$0.isEmpty }
        guard !validEncodedImages.isEmpty else { return nil }

        let mimeType = Self.imageMIMEType(for: request.compressedImages)
        try Task.checkCancellation()

        MerianLog.general.debug(
            "[⏱ BENCH] Pre-flight (encode+auth): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - request.pipelineStartedAt), privacy: .public)s"
        )
        let inferenceStartedAt = CFAbsoluteTimeGetCurrent()
        let observationContextsJSON = Self.observationContextJSONStrings(
            from: request.submissionProjection.observationContexts
        )
        let validVisualMediaItems =
            request.visualMediaItems?.count == validEncodedImages.count
            ? request.visualMediaItems
            : nil
        let videoFrameCount = validVisualMediaItems?
            .filter { $0.kind == .videoFrame }
            .count
            ?? (request.submissionProjection.videoFilePaths.isEmpty
                ? nil
                : request.compressedImages.count)

        let videoR2ObjectKeys: [String]
        if request.submissionProjection.videoFilePaths.isEmpty {
            videoR2ObjectKeys = []
        } else {
            videoR2ObjectKeys = try await dependencies.uploadStagedVideoFiles(
                request.submissionProjection.videoFilePaths,
                request.clientScanId
            )
            try validateAttempt()
        }

        onProviderDispatchReady()
        let resultData = try await dependencies.identify(
            ProviderRequest(
                // Inline images have no staged source object. A destination
                // filename is not an uploaded staging key.
                r2ObjectKeys: [],
                base64ImageDatas: validEncodedImages,
                mimeType: mimeType,
                audioFilePaths: request.submissionProjection.audioFilePaths,
                videoR2ObjectKeys: videoR2ObjectKeys,
                videoFrameCount: videoFrameCount,
                visualMediaItems: validVisualMediaItems,
                audioMediaItems:
                    request.submissionProjection.audioMediaItems,
                ownerMediaTimeline: request.ownerMediaTimeline,
                observationContextsJSON: observationContextsJSON,
                telemetry: request.telemetry,
                clientScanId: request.clientScanId,
                preferredGoal: request.preferredGoal,
                durableQueueOwnsRecovery:
                    request.durableQueueOwnsRecovery
            ),
            onRequestBodySent
        )
        try validateAttempt()

        let receivedAt = CFAbsoluteTimeGetCurrent()
        MerianLog.general.debug(
            "Gemini inference completed in \(String(format: "%.3f", receivedAt - inferenceStartedAt), privacy: .public)s."
        )
        return Response(
            resultData: resultData,
            observationContextsJSON: observationContextsJSON,
            receivedAt: receivedAt
        )
    }

    @MainActor
    func dispatchNonVisual(
        _ request: NonVisualRequest,
        validateAttempt: @MainActor () throws -> Void
    ) async throws -> Response {
        let observationContextsJSON = Self.observationContextJSONStrings(
            from: request.submissionProjection.observationContexts
        )
        try validateAttempt()
        let resultData = try await dependencies.identify(
            ProviderRequest(
                r2ObjectKeys: [],
                base64ImageDatas: [],
                mimeType: "image/webp",
                audioFilePaths: request.submissionProjection.audioFilePaths,
                videoR2ObjectKeys: [],
                videoFrameCount: nil,
                visualMediaItems: nil,
                audioMediaItems:
                    request.submissionProjection.audioMediaItems,
                ownerMediaTimeline: request.ownerMediaTimeline,
                observationContextsJSON: observationContextsJSON,
                telemetry: request.telemetry,
                clientScanId: request.clientScanId,
                preferredGoal: nil,
                durableQueueOwnsRecovery:
                    request.durableQueueOwnsRecovery
            ),
            nil
        )
        try validateAttempt()
        return Response(
            resultData: resultData,
            observationContextsJSON: observationContextsJSON,
            receivedAt: CFAbsoluteTimeGetCurrent()
        )
    }

    private static func imageMIMEType(for images: [Data]) -> String {
        guard let first = images.first, first.count >= 3 else {
            return "image/webp"
        }
        let prefix = [UInt8](first.prefix(3))
        return prefix == [0xFF, 0xD8, 0xFF]
            ? "image/jpeg"
            : "image/webp"
    }

    private static func observationContextJSONStrings(
        from contexts: [ObservationContext]
    ) -> [String] {
        contexts.compactMap { context in
            (try? JSONEncoder().encode(context)).flatMap {
                String(data: $0, encoding: .utf8)
            }
        }
    }
}
