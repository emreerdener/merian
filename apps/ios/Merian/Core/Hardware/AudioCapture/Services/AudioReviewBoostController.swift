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
    private var preparations: [UUID: Task<Void, Never>] = [:]
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
            defer { self?.preparations.removeValue(forKey: request) }
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
        preparations[request] = preparationTask
        return true
    }

    /// Cancellation revokes delivery immediately, but custody cannot move
    /// until every source reader has actually returned, including replaced work.
    func drain() async {
        await retireReaders().value
    }

    func retireReaders() -> Task<Void, Never> {
        suspend()
        let pending = Array(preparations.values) + Array(retirements.values)
        for task in pending { task.cancel() }
        return Task { for task in pending { await task.value } }
    }

    /// A stopped or unmounted review must not autoplay when preparation returns.
    func suspend() {
        generation = UUID()
        preparationTask?.cancel()
        preparationTask = nil
        state.isPreparing = false
    }

    func rejectPreparedAudio(after playback: Task<Void, Never>? = nil) {
        removePreparedAudio(after: playback)
        preparedURL = nil
        state.isReady = false
        state.isEnabled = false
        state.hasFailed = true
    }

    func reset(after playback: Task<Void, Never>? = nil) {
        suspend()
        removePreparedAudio(after: playback)
        preparedURL = nil
        sourceURL = nil
        state = AudioReviewBoostState()
    }

    private func removePreparedAudio(after playback: Task<Void, Never>?) {
        guard let preparedURL else { return }
        let remove = dependencies.remove
        if let playback {
            let id = UUID()
            retirements[id] = Task { [self] in
                defer { retirements[id] = nil }
                await playback.value
                remove(preparedURL)
            }
        } else { remove(preparedURL) }
    }

    private var retirements: [UUID: Task<Void, Never>] = [:]
}
