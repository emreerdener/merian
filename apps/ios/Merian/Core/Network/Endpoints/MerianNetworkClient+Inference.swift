import Foundation
import os

extension MerianNetworkClient {
    /// Direct requests retain the reviewed long provider window because their
    /// caller owns any retry or recovery UI.
    private static let directIdentifyRequestTimeout: TimeInterval = 90

    /// A durable queue can take over safely after this foreground window. The
    /// 15-second bound is more than twice the documented six-second cache-hit
    /// end-to-end p95 target while preventing a black-holed path from holding
    /// the live Insight in analysis for the direct caller's 90-second window.
    private static let queueBackedForegroundIdentifyRequestTimeout: TimeInterval = 15

    /// Opens the actual pinned inference connection pool used by live scans.
    /// Authentication is prewarmed separately because Supabase Auth owns a
    /// different URLSession.
    func prewarmInferenceEndpoint() async {
        do {
            try await performInferenceTransportPrewarm()
        } catch {
            MerianLog.network.debug(
                "Inference endpoint prewarm skipped; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
        }
    }

    /// Builds a fully-authenticated POST URLRequest for the /identify edge function.
    ///
    /// Returns the request without executing it so the caller can dispatch it as a
    /// background URLSession download task — enabling result delivery while backgrounded.
    func buildIdentifyRequest(
        r2ObjectKeys: [String],
        telemetry: CaptureTelemetry,
        clientScanId: String,
        description: String? = nil,
        observationContextJSON: String? = nil
    ) async throws -> AuthenticatedInferenceRequest {
        try await ensureInferenceConsent()
        try validateEndpointConfiguration("identify")
        let (context, expectedAuthUserID) = try await makeInferencePayloadContext(
            telemetry: telemetry
        )
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedScanId = clientScanId
        let capturedTelemetry = telemetry
        let capturedDescription = description
        let capturedObservationContextJSON = observationContextJSON
        let bodyData = try await DetachedWork.value(
            category: .inferenceRequestPreparation
        ) {
            try Task.checkCancellation()
            let bodyData = try InferencePayloadBuilder.identifyBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                imageBase64s: nil,
                mimeType: "image/webp",
                telemetry: capturedTelemetry,
                context: context,
                clientScanId: capturedScanId,
                description: capturedDescription,
                observationContextJSON: capturedObservationContextJSON
            )
            try Task.checkCancellation()
            return bodyData
        }

        guard Self.inferenceObjectKeysBelongToExpectedUser(
            [capturedR2ObjectKeys],
            expectedAuthUserID: expectedAuthUserID
        ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        let request = try await makeAuthenticatedInferenceURLRequest(
            function: "identify",
            bodyData: bodyData,
            idempotencyKey: capturedScanId,
            expectedAuthUserID: expectedAuthUserID
        )
        return AuthenticatedInferenceRequest(
            request: request,
            expectedAuthUserID: expectedAuthUserID
        )
    }

    func analyzeSubject(
        r2ObjectKeys: [String]?,
        base64ImageDatas: [String]?,
        mimeType: String = "image/webp",
        telemetry: CaptureTelemetry,
        clientScanId: String? = nil,
        description: String? = nil,
        observationContextJSON: String? = nil
    ) async throws -> Data {
        try await ensureInferenceConsent()
        try validateEndpointConfiguration("identify")
        let (context, expectedAuthUserID) = try await makeInferencePayloadContext(
            telemetry: telemetry
        )
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedImageBase64s = base64ImageDatas
        let capturedMimeType = mimeType
        let capturedTelemetry = telemetry
        let capturedClientScanId = clientScanId ?? UUID().uuidString.lowercased()
        let capturedDescription = description
        let capturedObservationContextJSON = observationContextJSON
        guard Self.inferenceObjectKeysBelongToExpectedUser(
            [capturedR2ObjectKeys ?? []],
            expectedAuthUserID: expectedAuthUserID
        ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        let bodyData = try await DetachedWork.value(
            category: .inferenceRequestPreparation
        ) {
            try Task.checkCancellation()
            let bodyData = try InferencePayloadBuilder.identifyBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                imageBase64s: capturedImageBase64s,
                mimeType: capturedMimeType,
                telemetry: capturedTelemetry,
                context: context,
                clientScanId: capturedClientScanId,
                description: capturedDescription,
                observationContextJSON: capturedObservationContextJSON
            )
            try Task.checkCancellation()
            return bodyData
        }

        // Inference calls can take up to 25–30s on gemini-2.5-pro with slow connections.
        // Use a 90s timeout matching timeoutIntervalForResource to prevent false timeouts.
        return try await performAuthenticatedInferenceJSONPost(
            function: "identify",
            body: bodyData,
            timeoutInterval: Self.directIdentifyRequestTimeout,
            idempotencyKey: capturedClientScanId,
            expectedAuthUserID: expectedAuthUserID
        )
    }

    static func buildMultiModalRequestBody(
        r2ObjectKeys: [String] = [],
        audioR2ObjectKeys: [String] = [],
        videoR2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        audioBase64s: [String] = [],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]? = nil,
        observationContextsJSON: [String] = [],
        userId: String,
        mimeType: String = "image/webp",
        telemetry: CaptureTelemetry,
        deviceLocale: String,
        deviceTimeZone: String,
        deviceRegion: String?,
        currentMonth: Int,
        timeOfDay: String,
        depthScaleText: String?,
        clientScanId: String,
        defaultGeoprivacy: String = "open",
        preferredGoal: FieldTripPreferredGoal? = nil
    ) throws -> Data {
        let context = InferencePayloadContext(
            userId: userId.lowercased(),
            deviceLocale: deviceLocale,
            deviceTimeZone: deviceTimeZone,
            deviceRegion: deviceRegion,
            currentMonth: currentMonth,
            timeOfDay: timeOfDay,
            depthScaleText: depthScaleText,
            defaultGeoprivacy: InferencePayloadBuilder.normalizedGeoprivacy(
                defaultGeoprivacy
            )
        )

        return try InferencePayloadBuilder.multimodalBody(
            r2ObjectKeys: r2ObjectKeys,
            audioR2ObjectKeys: audioR2ObjectKeys,
            videoR2ObjectKeys: videoR2ObjectKeys,
            imageBase64s: base64ImageDatas,
            audioBase64s: audioBase64s,
            videoFrameCount: videoFrameCount,
            visualMediaItems: visualMediaItems,
            audioMediaItems: audioMediaItems,
            ownerMediaTimeline: ownerMediaTimeline,
            observationContextsJSON: observationContextsJSON,
            mimeType: mimeType,
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId,
            preferredGoal: preferredGoal
        )
    }

    func buildMultiModalRequest(
        r2ObjectKeys: [String] = [],
        audioR2ObjectKeys: [String] = [],
        videoR2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        mimeType: String = "image/webp",
        audioFilePaths: [String] = [],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]? = nil,
        observationContextsJSON: [String] = [],
        telemetry: CaptureTelemetry,
        clientScanId: String,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) async throws -> AuthenticatedInferenceRequest {
        try await ensureInferenceConsent()
        try validateEndpointConfiguration("identify-multimodal")
        let (context, expectedAuthUserID) = try await makeInferencePayloadContext(
            telemetry: telemetry
        )
        let capturedR2ObjectKeys = r2ObjectKeys
        let capturedBase64ImageDatas = base64ImageDatas
        let capturedClientScanId = clientScanId

        let capturedAudioPaths = audioFilePaths
        let capturedAudioR2ObjectKeys = audioR2ObjectKeys
        let capturedVideoR2ObjectKeys = videoR2ObjectKeys
        let capturedVideoFrameCount = videoFrameCount
        let capturedVisualMediaItems = visualMediaItems
        let capturedAudioMediaItems = audioMediaItems
        let capturedOwnerMediaTimeline = ownerMediaTimeline
        let capturedContextsJSON = observationContextsJSON
        let capturedTelemetry = telemetry
        let capturedMimeType = mimeType
        let capturedPreferredGoal = preferredGoal

        let bodyData = try await DetachedWork.value(
            category: .inferenceRequestPreparation
        ) {
            try Task.checkCancellation()
            let audioBase64s = try Self.loadInlineAudioBase64s(
                from: capturedAudioPaths
            )
            try Task.checkCancellation()
            let bodyData = try Self.buildMultiModalRequestBody(
                r2ObjectKeys: capturedR2ObjectKeys,
                audioR2ObjectKeys: capturedAudioR2ObjectKeys,
                videoR2ObjectKeys: capturedVideoR2ObjectKeys,
                base64ImageDatas: capturedBase64ImageDatas,
                audioBase64s: audioBase64s,
                videoFrameCount: capturedVideoFrameCount,
                visualMediaItems: capturedVisualMediaItems,
                audioMediaItems: capturedAudioMediaItems,
                ownerMediaTimeline: capturedOwnerMediaTimeline,
                observationContextsJSON: capturedContextsJSON,
                userId: context.userId,
                mimeType: capturedMimeType,
                telemetry: capturedTelemetry,
                deviceLocale: context.deviceLocale,
                deviceTimeZone: context.deviceTimeZone,
                deviceRegion: context.deviceRegion,
                currentMonth: context.currentMonth,
                timeOfDay: context.timeOfDay,
                depthScaleText: context.depthScaleText,
                clientScanId: capturedClientScanId,
                defaultGeoprivacy: context.defaultGeoprivacy,
                preferredGoal: capturedPreferredGoal
            )
            try Task.checkCancellation()
            return bodyData
        }

        guard Self.inferenceObjectKeysBelongToExpectedUser(
            [
                capturedR2ObjectKeys,
                capturedAudioR2ObjectKeys,
                capturedVideoR2ObjectKeys
            ],
            expectedAuthUserID: expectedAuthUserID
        ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        let request = try await makeAuthenticatedInferenceURLRequest(
            function: "identify-multimodal",
            bodyData: bodyData,
            idempotencyKey: capturedClientScanId,
            expectedAuthUserID: expectedAuthUserID
        )
        return AuthenticatedInferenceRequest(
            request: request,
            expectedAuthUserID: expectedAuthUserID
        )
    }

    func identifyMultiModal(
        r2ObjectKeys: [String] = [],
        base64ImageDatas: [String] = [],
        mimeType: String = "image/webp",
        audioFilePaths: [String] = [],
        videoR2ObjectKeys: [String] = [],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]? = nil,
        observationContextsJSON: [String] = [],
        telemetry: CaptureTelemetry,
        clientScanId: String? = nil,
        preferredGoal: FieldTripPreferredGoal? = nil,
        durableQueueOwnsRecovery: Bool = false,
        onRequestBodySent: (@Sendable () -> Void)? = nil
    ) async throws -> Data {
        let authenticatedRequest = try await buildMultiModalRequest(
            r2ObjectKeys: r2ObjectKeys,
            videoR2ObjectKeys: videoR2ObjectKeys,
            base64ImageDatas: base64ImageDatas,
            mimeType: mimeType,
            audioFilePaths: audioFilePaths,
            videoFrameCount: videoFrameCount,
            visualMediaItems: visualMediaItems,
            audioMediaItems: audioMediaItems,
            ownerMediaTimeline: ownerMediaTimeline,
            observationContextsJSON: observationContextsJSON,
            telemetry: telemetry,
            clientScanId: clientScanId ?? UUID().uuidString.lowercased(),
            preferredGoal: preferredGoal
        )

        return try await performAuthenticatedInferenceRequest(
            authenticatedRequest,
            timeoutInterval: durableQueueOwnsRecovery
                ? Self.queueBackedForegroundIdentifyRequestTimeout
                : Self.directIdentifyRequestTimeout,
            // Once the durable queue owns recovery, suppress the shared transient
            // URLError replay. Auth refresh, route propagation, and idempotent 5xx
            // handling remain owned by the common authenticated transport.
            allowsTransientTransportRetry: !durableQueueOwnsRecovery,
            onRequestBodySent: onRequestBodySent
        )
    }

    private func ensureInferenceConsent() async throws {
        #if DEBUG
        if let overridingInferenceConsentCheck {
            try await overridingInferenceConsentCheck()
            return
        }
        #endif
        try await ConsentManager.shared.ensureCloudConsentForInference()
    }

    private func makeInferencePayloadContext(
        telemetry: CaptureTelemetry
    ) async throws -> (InferencePayloadContext, UUID) {
        let authUserID = try await authenticatedUserIDForInferenceRequest()
        let defaultGeoprivacy = await MainActor.run {
            AppDIContainer.shared.profileViewModel.defaultGeoprivacy
        }
        return (
            InferencePayloadBuilder.makeContext(
                userId: authUserID.uuidString,
                telemetry: telemetry,
                defaultGeoprivacy: defaultGeoprivacy
            ),
            authUserID
        )
    }

    private static func loadInlineAudioBase64s(
        from audioFilePaths: [String]
    ) throws -> [String] {
        guard !audioFilePaths.isEmpty else { return [] }
        try Task.checkCancellation()

        let fileURLs = audioFilePaths.map { path -> URL in
            let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.hasPrefix("/")
                ? URL(fileURLWithPath: normalized)
                : URL.documentsDirectory.appendingPathComponent(normalized)
        }
        try InferenceMediaPolicy.validateAudioFiles(fileURLs: fileURLs)
        try Task.checkCancellation()

        var audioBase64s: [String] = []
        audioBase64s.reserveCapacity(audioFilePaths.count)

        for url in fileURLs {
            try Task.checkCancellation()
            let wavData = try Data(contentsOf: url, options: [.mappedIfSafe])
            audioBase64s.append(wavData.base64EncodedString())
        }
        try Task.checkCancellation()

        return audioBase64s
    }
}
