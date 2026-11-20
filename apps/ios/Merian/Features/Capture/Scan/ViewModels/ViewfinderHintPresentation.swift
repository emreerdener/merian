import Foundation
import Observation

/// Retained by the app container, so remounting a camera never replays its introduction.
@MainActor
final class ViewfinderHintLaunchState {
    private var hasStarted = false

    func claimIntroduction() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }
}

@MainActor
@Observable
final class ViewfinderHintPresentation {
    enum Phase: Hashable {
        case identify, video, refinement, finished

        var text: String? {
            switch self {
            case .identify: "Tap to identify"
            case .video: "Hold to record video"
            case .refinement: "Add another"
            case .finished: nil
            }
        }
    }

    struct Context: Equatable {
        var isVisible = false
        var hasEmptyDraft = true
        var isRefining = false
        var isCapturing = false
        var canRecordVideo = false
        var keepsPromptVisible = false
    }

    private(set) var phase: Phase = .finished
    private(set) var allowsGuidance = false
    @ObservationIgnored private var context = Context()
    @ObservationIgnored private var hasShownRefinement = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    init(sleep: @escaping @MainActor (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }) {
        self.sleep = sleep
    }

    func update(_ newContext: Context, claimIntroduction: () -> Bool) {
        context = newContext
        if !context.isRefining { hasShownRefinement = false }
        guard context.isVisible, !context.isCapturing else {
            hide()
            return
        }
        if context.isRefining {
            if !hasShownRefinement {
                hasShownRefinement = true
                start(.refinement)
            } else if phase == .finished, task == nil {
                allowsGuidance = true
            }
            return
        }
        if phase == .refinement {
            finish()
        }
        guard context.hasEmptyDraft else {
            if phase == .identify || phase == .video { finish() }
            if phase == .finished, task == nil { allowsGuidance = true }
            return
        }
        if phase == .video, !context.canRecordVideo {
            finish()
        } else if phase == .finished, claimIntroduction() {
            start(.identify)
        } else if phase == .finished, task == nil {
            allowsGuidance = true
        }
    }

    func hide() {
        cancelTask()
        phase = .finished
        allowsGuidance = false
    }

    private func cancelTask() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func start(_ phase: Phase) {
        cancelTask()
        self.phase = phase
        allowsGuidance = false
        guard !context.keepsPromptVisible else { return }
        let token = generation
        task = Task { @MainActor [weak self, sleep] in
            do { try await sleep(.milliseconds(3500)) } catch { return }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            if self.phase == .identify, self.context.canRecordVideo {
                self.start(.video)
            } else {
                self.finish()
            }
        }
    }

    private func finish() {
        cancelTask()
        phase = .finished
        allowsGuidance = false
        let token = generation
        task = Task { @MainActor [weak self, sleep] in
            do { try await sleep(.milliseconds(350)) } catch { return }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.allowsGuidance = true
            self.task = nil
        }
    }
}
