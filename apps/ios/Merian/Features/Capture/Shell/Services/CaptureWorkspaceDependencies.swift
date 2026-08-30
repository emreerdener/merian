import Foundation

typealias RefinementImageDownloader = @Sendable (URL) async throws -> URL?

struct CaptureWorkspaceFeedback {
    let selection: @MainActor (_ source: String) -> Void
    let sheet: @MainActor (_ source: String?) -> Void
    let medium: @MainActor () -> Void
    let error: @MainActor () -> Void
}

struct CaptureWorkspaceDependencies {
    let scan: CaptureScanDependencies
    let submission: CaptureSubmissionDependencies
    let prepareImage: PreparedStagedImageLoader
    let prepareHistoricalAudio: PreparedHistoricalAudioLoader
    let externalImageImports: ExternalImageImportStore
    let downloadRefinementImage: RefinementImageDownloader
    let prewarmConnections: @MainActor @Sendable () async -> Void
    let sharedExplorePostId: @MainActor (_ scanId: String) -> String?
    let captureGoalAccountId: @MainActor (_ userId: UUID?) -> String?
    let feedback: CaptureWorkspaceFeedback

    @MainActor
    static func live(
        diContainer: AppDIContainer,
        preparedImageLoader: @escaping PreparedStagedImageLoader = livePreparedImageLoader,
        preparedHistoricalAudioLoader: @escaping PreparedHistoricalAudioLoader =
            livePreparedHistoricalAudioLoader,
        externalImageImportStore: ExternalImageImportStore? = nil
    ) -> Self {
        Self(
            scan: .live(diContainer: diContainer),
            submission: .live(diContainer: diContainer),
            prepareImage: preparedImageLoader,
            prepareHistoricalAudio: preparedHistoricalAudioLoader,
            externalImageImports: externalImageImportStore
                ?? diContainer.externalImageImportStore,
            downloadRefinementImage: { remoteURL in
                try await CaptureWorkspaceRemoteMediaService.downloadImage(
                    from: remoteURL
                )
            },
            prewarmConnections: {
                async let authWarmup: Void = {
                    _ = try? await diContainer.supabaseManager.getValidAuthHeaders()
                }()
                async let inferenceWarmup: Void = MerianNetworkClient.shared
                    .prewarmInferenceEndpoint()
                _ = await (authWarmup, inferenceWarmup)
            },
            sharedExplorePostId: { scanId in
                ExploreShareStateStore.sharedPostId(for: scanId)
            },
            captureGoalAccountId: { userId in
                #if DEBUG
                if let seededAccountId = UITestSeedCoordinator
                    .captureGoalAccountId {
                    return seededAccountId
                }
                #endif
                return userId?.uuidString
            },
            feedback: .init(
                selection: { source in
                    HapticManager.shared.triggerSelectionPulse(source: source)
                },
                sheet: { source in
                    if let source {
                        HapticManager.shared.triggerSheetSpring(source: source)
                    } else {
                        HapticManager.shared.triggerSheetSpring()
                    }
                },
                medium: {
                    HapticManager.shared.triggerMediumPulse()
                },
                error: {
                    HapticManager.shared.triggerErrorThump()
                }
            )
        )
    }

    nonisolated static let livePreparedImageLoader: PreparedStagedImageLoader = { request in
        let prepared = try await MediaPreparationActor.shared.prepareStillImage(
            fileURL: request.fileURL,
            isPro: request.isPro
        )
        let focusRegion = await ImageFocusRegionDetector.detect(in: prepared.inferenceData)
        return PreparedStagedImage(
            compressedData: prepared.inferenceData,
            displayData: prepared.displayData,
            historicalContext: request.historicalContext,
            previewCGImage: SendableCGImage(image: prepared.previewImage.cgImage),
            metrics: prepared.metrics,
            focusRegion: focusRegion
        )
    }

    nonisolated static let livePreparedHistoricalAudioLoader: PreparedHistoricalAudioLoader = {
        try await InferenceAudioPreparer.prepareHistoricalReference($0)
    }
}

private enum CaptureWorkspaceRemoteMediaService {
    nonisolated static func downloadImage(from remoteURL: URL) async throws -> URL? {
        guard SecureTransportPolicy.isSecureRemoteURL(remoteURL) else {
            throw URLError(.unsupportedURL)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil

        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (downloadURL, response) = try await session.download(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let extensionHint = remoteURL.pathExtension.isEmpty
            ? "jpg"
            : remoteURL.pathExtension
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(extensionHint)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
        return destinationURL
    }
}
