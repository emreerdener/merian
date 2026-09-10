import Foundation
import os

/// Owns the complete lock-protected lifetime of one video-recording request.
///
/// AVFoundation objects and camera-queue operations remain in
/// `CameraVideoRecordingService`. This coordinator owns only request identity,
/// continuation lifetime, start metadata, scheduled-action tasks, and the
/// atomic transitions that arbitrate stop, timeout, cancellation, and delegate
/// completion.
final class CameraVideoRecordingCoordinator: Sendable {
    typealias Sleeper = @Sendable (UInt64) async -> Void
    typealias StartHandler = @MainActor @Sendable () -> Void
    typealias ScheduledActionHandler = @Sendable (
        CameraVideoRecordingScheduledAction
    ) -> Void

    struct StartContext: Sendable {
        let generation: CameraVideoRecordingGeneration
        let handler: StartHandler?
        let maxDuration: TimeInterval
        let stopWasRequested: Bool
    }

    struct Completion: Sendable {
        let generation: CameraVideoRecordingGeneration
        let startedAt: Date?

        private let continuation: CompletionContinuationBox

        fileprivate init(
            generation: CameraVideoRecordingGeneration,
            startedAt: Date?,
            continuation: CheckedContinuation<CameraVideoRecording, Error>
        ) {
            self.generation = generation
            self.startedAt = startedAt
            self.continuation = CompletionContinuationBox(continuation)
        }

        @discardableResult
        func resume(returning recording: CameraVideoRecording) -> Bool {
            continuation.resume(with: .success(recording))
        }

        @discardableResult
        func resume(throwing error: Error) -> Bool {
            continuation.resume(with: .failure(error))
        }
    }

    private final class CompletionContinuationBox: Sendable {
        private let storage: OSAllocatedUnfairLock<
            CheckedContinuation<CameraVideoRecording, Error>?
        >

        init(_ continuation: CheckedContinuation<CameraVideoRecording, Error>) {
            storage = OSAllocatedUnfairLock(initialState: continuation)
        }

        func resume(with result: Result<CameraVideoRecording, Error>) -> Bool {
            let continuation = storage.withLock { continuation in
                defer { continuation = nil }
                return continuation
            }
            guard let continuation else { return false }
            continuation.resume(with: result)
            return true
        }
    }

    private struct ScheduledTask {
        let action: CameraVideoRecordingScheduledAction
        var task: Task<Void, Never>?
    }

    private struct ActiveRequest {
        var gate: CameraVideoRecordingGenerationGate
        let continuation: CheckedContinuation<CameraVideoRecording, Error>
        var startedAt: Date?
        let maxDuration: TimeInterval
        var startHandler: StartHandler?
        var timeoutTask: ScheduledTask?
        var stopTask: ScheduledTask?
        var stopWasRequested = false
    }

    private struct State {
        var activeRequest: ActiveRequest?
    }

    private enum ScheduledActionKind {
        case timeout
        case stop
    }

    private let sleep: Sleeper
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        sleep: @escaping Sleeper = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.sleep = sleep
    }

    @discardableResult
    func install(
        generation: CameraVideoRecordingGeneration,
        maxDuration: TimeInterval,
        startHandler: StartHandler?,
        continuation: CheckedContinuation<CameraVideoRecording, Error>
    ) -> Bool {
        state.withLock { state in
            guard state.activeRequest == nil else { return false }
            state.activeRequest = ActiveRequest(
                gate: CameraVideoRecordingGenerationGate(generation: generation),
                continuation: continuation,
                startedAt: nil,
                maxDuration: maxDuration,
                startHandler: startHandler,
                timeoutTask: nil,
                stopTask: nil
            )
            return true
        }
    }

    var activeGeneration: CameraVideoRecordingGeneration? {
        state.withLock { $0.activeRequest?.gate.generation }
    }

    func isActive(_ generation: CameraVideoRecordingGeneration) -> Bool {
        state.withLock {
            $0.activeRequest?.gate.matches(generation) == true
        }
    }

    @discardableResult
    func claimStop(
        generation: CameraVideoRecordingGeneration,
        scheduledAction: CameraVideoRecordingScheduledAction?
    ) -> Bool {
        let claim = state.withLock { state -> (accepted: Bool, task: Task<Void, Never>?) in
            guard var active = state.activeRequest,
                  active.gate.matches(generation),
                  !active.stopWasRequested else {
                return (false, nil)
            }
            if let scheduledAction {
                guard active.gate.acceptsStopAction(scheduledAction),
                      active.stopTask?.action == scheduledAction else {
                    return (false, nil)
                }
            }

            let task = active.stopTask?.task
            active.stopTask = nil
            active.gate.clearStopAction()
            active.stopWasRequested = true
            state.activeRequest = active
            return (true, task)
        }

        guard claim.accepted else { return false }
        claim.task?.cancel()
        return true
    }

    func claimStart(
        callbackURL: URL,
        startedAt: Date = Date()
    ) -> StartContext? {
        state.withLock { state in
            guard var active = state.activeRequest,
                  active.gate.matches(callbackURL: callbackURL),
                  active.startedAt == nil else {
                return nil
            }

            active.startedAt = startedAt
            let context = StartContext(
                generation: active.gate.generation,
                handler: active.startHandler,
                maxDuration: active.maxDuration,
                stopWasRequested: active.stopWasRequested
            )
            active.startHandler = nil
            state.activeRequest = active
            return context
        }
    }

    @discardableResult
    func scheduleTimeout(
        for generation: CameraVideoRecordingGeneration,
        after seconds: TimeInterval,
        fire: @escaping ScheduledActionHandler
    ) -> CameraVideoRecordingScheduledAction? {
        schedule(
            kind: .timeout,
            for: generation,
            after: seconds,
            fire: fire
        )
    }

    func isCurrentTimeout(
        _ action: CameraVideoRecordingScheduledAction
    ) -> Bool {
        state.withLock { state in
            guard let active = state.activeRequest else { return false }
            return active.gate.acceptsTimeoutAction(action)
                && active.timeoutTask?.action == action
        }
    }

    @discardableResult
    func scheduleStop(
        for generation: CameraVideoRecordingGeneration,
        after seconds: TimeInterval,
        fire: @escaping ScheduledActionHandler
    ) -> CameraVideoRecordingScheduledAction? {
        schedule(
            kind: .stop,
            for: generation,
            after: seconds,
            fire: fire
        )
    }

    func take(
        generation: CameraVideoRecordingGeneration,
        expectedTimeoutAction: CameraVideoRecordingScheduledAction? = nil
    ) -> Completion? {
        let request = state.withLock { state -> ActiveRequest? in
            guard let active = state.activeRequest,
                  active.gate.matches(generation) else {
                return nil
            }
            if let expectedTimeoutAction {
                guard active.gate.acceptsTimeoutAction(expectedTimeoutAction),
                      active.timeoutTask?.action == expectedTimeoutAction else {
                    return nil
                }
            }

            state.activeRequest = nil
            return active
        }
        return completion(from: request)
    }

    func take(callbackURL: URL) -> Completion? {
        let request = state.withLock { state -> ActiveRequest? in
            guard let active = state.activeRequest,
                  active.gate.matches(callbackURL: callbackURL) else {
                return nil
            }

            state.activeRequest = nil
            return active
        }
        return completion(from: request)
    }

    private func schedule(
        kind: ScheduledActionKind,
        for generation: CameraVideoRecordingGeneration,
        after seconds: TimeInterval,
        fire: @escaping ScheduledActionHandler
    ) -> CameraVideoRecordingScheduledAction? {
        let delay = UInt64(max(seconds, 0.1) * 1_000_000_000)
        let action = CameraVideoRecordingScheduledAction(
            generation: generation,
            id: UUID()
        )
        let installation = installScheduledAction(action, kind: kind)
        guard installation.installed else { return nil }
        installation.previous?.cancel()

        let sleep = sleep
        let task = Task {
            await sleep(delay)
            guard !Task.isCancelled else { return }
            fire(action)
        }

        if !attach(task, to: action, kind: kind) {
            task.cancel()
        }
        return action
    }

    private func installScheduledAction(
        _ action: CameraVideoRecordingScheduledAction,
        kind: ScheduledActionKind
    ) -> (installed: Bool, previous: Task<Void, Never>?) {
        state.withLock { state in
            guard var active = state.activeRequest else {
                return (false, nil)
            }

            let previous: Task<Void, Never>?
            switch kind {
            case .timeout:
                guard active.gate.installTimeoutAction(action) else {
                    return (false, nil)
                }
                previous = active.timeoutTask?.task
                active.timeoutTask = ScheduledTask(action: action, task: nil)
            case .stop:
                guard active.gate.installStopAction(action) else {
                    return (false, nil)
                }
                previous = active.stopTask?.task
                active.stopTask = ScheduledTask(action: action, task: nil)
            }

            state.activeRequest = active
            return (true, previous)
        }
    }

    private func attach(
        _ task: Task<Void, Never>,
        to action: CameraVideoRecordingScheduledAction,
        kind: ScheduledActionKind
    ) -> Bool {
        state.withLock { state in
            guard var active = state.activeRequest else { return false }

            switch kind {
            case .timeout:
                guard active.gate.acceptsTimeoutAction(action),
                      var scheduledTask = active.timeoutTask,
                      scheduledTask.action == action else {
                    return false
                }
                scheduledTask.task = task
                active.timeoutTask = scheduledTask
            case .stop:
                guard active.gate.acceptsStopAction(action),
                      var scheduledTask = active.stopTask,
                      scheduledTask.action == action else {
                    return false
                }
                scheduledTask.task = task
                active.stopTask = scheduledTask
            }

            state.activeRequest = active
            return true
        }
    }

    private func completion(from request: ActiveRequest?) -> Completion? {
        guard let request else { return nil }
        request.timeoutTask?.task?.cancel()
        request.stopTask?.task?.cancel()
        return Completion(
            generation: request.gate.generation,
            startedAt: request.startedAt,
            continuation: request.continuation
        )
    }
}
