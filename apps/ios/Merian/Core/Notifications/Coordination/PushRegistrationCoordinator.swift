import Foundation

/// Serializes remote registration and retains the newest state that arrives
/// while a request is suspended. A successful request satisfies an equal
/// trailing snapshot; a failed request still attempts an equal snapshot that
/// arrived while the failed request was in flight.
@MainActor
final class PushRegistrationCoordinator {
    struct Dependencies {
        let service: PushRegistrationService
        let reportFailure:
            @MainActor (_ reason: String, _ error: any Error) -> Void

        @MainActor static var live: Self {
            Self(
                service: .live,
                reportFailure: { reason, error in
                    MerianLog.notifications.error(
                        "Remote push registration sync failed (\(reason, privacy: .public)): \(error.localizedDescription, privacy: .private)"
                    )
                }
            )
        }
    }

    private struct Work {
        let request: PushRegistrationRequest
        let reason: String
    }

    private let dependencies: Dependencies
    private var pendingWork: Work?
    private var activeRequest: PushRegistrationRequest?
    private var activeTask: Task<Void, Never>?
    private var activeGeneration: UUID?

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func synchronize(
        _ request: PushRegistrationRequest,
        reason: String
    ) async {
        pendingWork = Work(request: request, reason: reason)
        startDrainIfNeeded()
        await activeTask?.value
    }

    private func startDrainIfNeeded() {
        guard activeTask == nil else { return }

        let generation = UUID()
        let register = dependencies.service.register
        let reportFailure = dependencies.reportFailure
        activeGeneration = generation
        activeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled,
                  let work = self?.takeNextWork(generation: generation) {
                do {
                    try await register(work.request)
                    self?.finish(
                        work,
                        succeeded: true,
                        generation: generation
                    )
                } catch {
                    reportFailure(work.reason, error)
                    self?.finish(
                        work,
                        succeeded: false,
                        generation: generation
                    )
                }
            }
            self?.completeDrain(generation: generation)
        }
    }

    private func takeNextWork(generation: UUID) -> Work? {
        guard activeGeneration == generation,
              let work = pendingWork else { return nil }
        pendingWork = nil
        activeRequest = work.request
        return work
    }

    private func finish(
        _ work: Work,
        succeeded: Bool,
        generation: UUID
    ) {
        guard activeGeneration == generation,
              activeRequest == work.request else { return }
        activeRequest = nil

        if succeeded, pendingWork?.request == work.request {
            pendingWork = nil
        }
    }

    private func completeDrain(generation: UUID) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        activeRequest = nil
        activeTask = nil
    }
}
