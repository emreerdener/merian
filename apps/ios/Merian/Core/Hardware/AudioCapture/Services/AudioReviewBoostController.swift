import Foundation
import Observation

struct AudioReviewBoostState: Equatable {
    var isEnabled = false
    var isPreparing = false
    var isReady = false
    var hasFailed = false
}

/// Owns only temporary review derivatives, never the recording or submission path.
@MainActor
@Observable
final class AudioReviewBoostController {
    struct Dependencies: Sendable {
        let prepare: @Sendable (URL) async throws -> AudioBoostResult
        let remove: @Sendable (URL) -> Void

        static let live = Self(
            prepare: { try await AudioBoostProcessor.prepareLocalPreview(sourceURL: $0) },
            remove: { try? FileManager.default.removeItem(at: $0) }
        )
    }

    private(set) var state = AudioReviewBoostState()
    private(set) var preparedURL: URL?
    private var sourceURL: URL?
    private var generation = UUID()
    private var preparationTask: Task<Void, Never>?
    private let dependencies: Dependencies

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    var playbackURL: URL? { state.isEnabled ? preparedURL : nil }

    func configure(sourceURL: URL, enabled: Bool) {
        reset()
        self.sourceURL = sourceURL
        state.isEnabled = enabled
    }

    func toggle() {
        state.isEnabled.toggle()
        state.hasFailed = false
        if !state.isEnabled { suspend() }
    }

    /// Returns true while playback must wait for the selected source.
    @discardableResult
    func prepareIfNeeded(onReady: @escaping @MainActor () -> Void) -> Bool {
        guard state.isEnabled, preparedURL == nil, let sourceURL else { return false }
        guard !state.isPreparing else { return true }
        state.isPreparing = true
        state.hasFailed = false
        let request = UUID()
        generation = request
        let dependencies = dependencies
        preparationTask = Task { @MainActor [weak self] in
            do {
                let result = try await dependencies.prepare(sourceURL)
                guard let self, !Task.isCancelled, self.generation == request else {
                    dependencies.remove(result.url)
                    return
                }
                self.preparedURL = result.url
                self.state.isReady = true
                self.state.isPreparing = false
                self.preparationTask = nil
                onReady()
            } catch {
                guard let self, !Task.isCancelled, self.generation == request else { return }
                self.state.isPreparing = false
                self.state.isEnabled = false
                self.state.hasFailed = true
                self.preparationTask = nil
                onReady()
            }
        }
        return true
    }

    /// A stopped or unmounted review must not autoplay when preparation returns.
    func suspend() {
        generation = UUID()
        preparationTask?.cancel()
        preparationTask = nil
        state.isPreparing = false
    }

    func rejectPreparedAudio() {
        if let preparedURL { dependencies.remove(preparedURL) }
        preparedURL = nil
        state.isReady = false
        state.isEnabled = false
        state.hasFailed = true
    }

    func reset() {
        suspend()
        if let preparedURL { dependencies.remove(preparedURL) }
        preparedURL = nil
        sourceURL = nil
        state = AudioReviewBoostState()
    }
}
