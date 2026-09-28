import Foundation

/// One mounted preview owns its listening copy; it never enters the shared cache.
@MainActor
final class StagedPreviewAudioBoostSource {
    struct Dependencies: Sendable {
        let prepare: @Sendable (URL) async throws -> AudioBoostResult
        let remove: @Sendable (URL) -> Void

        static let live = Self(
            prepare: { try await AudioBoostProcessor.prepareLocalPreview(sourceURL: $0) },
            remove: { try? FileManager.default.removeItem(at: $0) }
        )
    }

    private let dependencies: Dependencies
    private var cached: AudioBoostResult?
    private var generation = UUID()

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    deinit {
        if let cached { dependencies.remove(cached.url) }
    }

    func prepare(source: String) async throws -> AudioBoostResult {
        try Task.checkCancellation()
        if let cached { return cached }
        let request = generation
        let original = try await AudioBoostProcessor.shared.acquireSource(source)
        defer { original.release() }
        try Task.checkCancellation()
        guard generation == request else { throw CancellationError() }
        let result = try await dependencies.prepare(original.url)
        guard !Task.isCancelled, generation == request else {
            dependencies.remove(result.url)
            throw CancellationError()
        }
        // Concurrent preparation never retires a copy already used by a player.
        if let cached {
            dependencies.remove(result.url)
            return cached
        }
        cached = result
        return result
    }

    /// Call only after the player has retired its boosted source.
    func release() {
        generation = UUID()
        if let cached { dependencies.remove(cached.url) }
        cached = nil
    }

    func playbackDependencies(base: MediaPlaybackDependencies? = nil) -> MediaPlaybackDependencies {
        let base = base ?? .live
        return MediaPlaybackDependencies(
            feedbackNamespace: "capture.preview",
            activatePlaybackAudio: base.activatePlaybackAudio,
            acquireAudioSource: base.acquireAudioSource,
            prepareAudioBoost: { [self] in try await prepare(source: $0) },
            releaseAudioBoost: { [self] _ in release() },
            invalidateAudioBoost: { [self] _ in release() },
            selectionFeedback: base.selectionFeedback,
            lightImpactFeedback: base.lightImpactFeedback,
            mediumPulseFeedback: base.mediumPulseFeedback,
            errorFeedback: base.errorFeedback
        )
    }
}
