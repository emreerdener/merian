import Foundation

/// Internal continuation of an already successful Identify submission. No
/// inference/upload API is exposed here. Durable candidates survive this worker;
/// its bounded retry timer owns neither an account lease nor deletion authority.
@MainActor
final class CaptureCompletedHistoryDrain {
    typealias Candidate = SharedMediaCaptureCompletedRecovery.Candidate
    struct Dependencies {
        let begin: () throws -> InferenceCompletionAccountScope
        let page: (String?, InferenceCompletionAccountScope) async throws -> SharedMediaCaptureCompletedRecovery.Page
        let finish: (Candidate, InferenceCompletionAccountScope) async throws -> Void
        var isCurrent: () -> Bool = { true }
        var canUseNetwork: () -> Bool = { true }
        var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    }

    private let dependencies: Dependencies
    private var active: Task<TimeInterval?, Never>?
    private var activeID: UUID?
    private var wake: Task<Void, Never>?
    private var wakeID: UUID?
    private var cursor: String?
    private var cursorOwner: UUID?
    private var sweepNeedsRetry = false
    private var freshSweepRequested = false
    private var failedSweeps = 0
    private(set) var isClosed = false
    var isRunning: Bool { active != nil }

    init(dependencies: Dependencies) { self.dependencies = dependencies }

    func drain() async {
        guard !isClosed, dependencies.isCurrent() else { return }
        if let active { freshSweepRequested = true; _ = await active.value; return }
        wake?.cancel(); wake = nil; wakeID = nil
        let id = UUID(), task = Task { @MainActor [self] in await pass() }
        activeID = id; active = task
        let delay = await task.value
        guard activeID == id else { return }
        active = nil; activeID = nil
        guard !isClosed, dependencies.isCurrent() else { return }
        if freshSweepRequested && cursor == nil {
            freshSweepRequested = false
            schedule(1)
        } else if let delay { schedule(delay) }
    }

    func close() async {
        isClosed = true
        let timer = wake, task = active
        wake = nil; wakeID = nil
        timer?.cancel(); task?.cancel()
        await timer?.value
        _ = await task?.value
        active = nil; activeID = nil
        cursor = nil; cursorOwner = nil; sweepNeedsRetry = false; freshSweepRequested = false
    }

    private func requireCurrent(_ account: InferenceCompletionAccountScope) throws {
        try Task.checkCancellation(); try account.validate()
        guard !isClosed, dependencies.isCurrent() else { throw SharedMediaStorageFailure.closed }
    }

    private func pass() async -> TimeInterval? {
        let account: InferenceCompletionAccountScope
        do { account = try dependencies.begin() } catch {
            return !Task.isCancelled && !isClosed && dependencies.isCurrent() ? retryDelay() : nil
        }
        defer { account.finish() }
        if cursorOwner != account.ownerID {
            cursorOwner = account.ownerID; cursor = nil; sweepNeedsRetry = false; failedSweeps = 0
        }
        do {
            for _ in 0..<8 {
                try requireCurrent(account)
                let page = try await dependencies.page(cursor, account)
                try requireCurrent(account)
                for candidate in page.candidates {
                    try requireCurrent(account)
                    // An existing release intent already proves enrollment and
                    // may finish offline. New enrollment waits for connectivity.
                    if !candidate.releaseStarted && !dependencies.canUseNetwork() {
                        sweepNeedsRetry = true; continue
                    }
                    do {
                        try await dependencies.finish(candidate, account)
                        try requireCurrent(account)
                    } catch {
                        try requireCurrent(account)
                        sweepNeedsRetry = true
                    }
                }
                cursor = page.nextCursor
                if cursor == nil {
                    let retry = sweepNeedsRetry; sweepNeedsRetry = false
                    if retry { return retryDelay() }
                    failedSweeps = 0
                    return nil
                }
                await Task.yield()
            }
            return 1
        } catch {
            guard !Task.isCancelled, !isClosed, dependencies.isCurrent() else { return nil }
            do { try account.validate() } catch { return nil }
            // Restart discovery after uncertainty. A candidate is only a hint;
            // finish rechecks the exact scan, generation and release progression.
            cursor = nil; sweepNeedsRetry = false
            return retryDelay()
        }
    }

    private func retryDelay() -> TimeInterval {
        let delay = min(300, 5 * pow(2, Double(failedSweeps)))
        failedSweeps = min(6, failedSweeps + 1)
        return delay
    }

    private func schedule(_ delay: TimeInterval) {
        let id = UUID(); wakeID = id
        wake = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await dependencies.sleep(delay) } catch { return }
            guard !Task.isCancelled, !isClosed, dependencies.isCurrent(), wakeID == id else { return }
            wake = nil; wakeID = nil
            await drain()
        }
    }
}
