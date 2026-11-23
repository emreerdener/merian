import Foundation

/// One retained worker per account lifetime. The host registers `close` before
/// the first drain; cancellation joins the actual upload/request/result task.
@MainActor
final class SharedMediaCaptureExecutionDrain {
    typealias Candidate = SharedMediaCaptureExecutionRecovery.Candidate
    struct Dependencies {
        let begin: () throws -> InferenceCompletionAccountScope
        let page: (String?, InferenceCompletionAccountScope) async throws -> SharedMediaCaptureExecutionRecovery.Page
        let claim: (Candidate, Date, InferenceCompletionAccountScope) async throws -> Candidate
        /// Prepare, reserve dispatch durably, then make one primary call. A
        /// dispatch-save error must return without making that call.
        let execute: (Candidate, InferenceCompletionAccountScope) async throws -> Void
        /// Returns true only when a durable automatic retry remains scheduled.
        let postpone: (Candidate, Date, InferenceCompletionAccountScope) async throws -> Bool
        /// This dependency must have no route to primary inference. Absence or
        /// unknown outcome remains held; it cannot fall back to `execute`.
        var recover: (Candidate, InferenceCompletionAccountScope) async throws -> Void = { _, _ in
            throw SharedMediaStorageFailure.unavailable
        }
        /// Waiting for a blocker is not an execution attempt. This dependency
        /// may resolve local funding but cannot dispatch inference.
        var prepareFunding: (Candidate, InferenceCompletionAccountScope) async throws -> Bool = { _, _ in true }
        var isCurrent: () -> Bool = { true }
        var canUseNetwork: () -> Bool = { true }
        var now: () -> Date = Date.init
        var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    }

    private let dependencies: Dependencies
    private var active: Task<Date?, Never>?
    private var activeID: UUID?
    private var wake: Task<Void, Never>?
    private var wakeID: UUID?
    private var cursor: String?
    private var cursorOwner: UUID?
    private var sweepDeadline: Date?
    private var freshSweepRequested = false
    private(set) var isClosed = false
    var isRunning: Bool { active != nil }

    init(dependencies: Dependencies) { self.dependencies = dependencies }

    func drain() async {
        guard !isClosed, dependencies.isCurrent() else { return }
        if let active { freshSweepRequested = true; _ = await active.value; return }
        wake?.cancel(); wake = nil; wakeID = nil
        guard dependencies.canUseNetwork() else { return }
        let id = UUID(), task = Task { @MainActor [self] in await pass() }
        activeID = id; active = task
        let next = await task.value
        guard activeID == id else { return }
        active = nil; activeID = nil
        guard !isClosed, dependencies.isCurrent() else { return }
        if freshSweepRequested && cursor == nil {
            freshSweepRequested = false
            schedule(min(next ?? .distantFuture, dependencies.now().addingTimeInterval(1)))
        } else if let next { schedule(next) }
    }

    func close() async {
        isClosed = true
        let timer = wake, task = active
        wake = nil; wakeID = nil
        timer?.cancel(); task?.cancel()
        await timer?.value
        _ = await task?.value
        active = nil; activeID = nil
        cursor = nil; cursorOwner = nil; sweepDeadline = nil; freshSweepRequested = false
    }

    private func requireCurrent(_ account: InferenceCompletionAccountScope) throws {
        try Task.checkCancellation(); try account.validate()
        guard !isClosed, dependencies.isCurrent() else { throw SharedMediaStorageFailure.closed }
    }

    private func pass() async -> Date? {
        let account: InferenceCompletionAccountScope
        do { account = try dependencies.begin() } catch {
            return !isClosed && dependencies.isCurrent() ? dependencies.now().addingTimeInterval(5) : nil
        }
        defer { account.finish() }
        if cursorOwner != account.ownerID { cursorOwner = account.ownerID; cursor = nil; sweepDeadline = nil }
        do {
            for _ in 0..<8 {
                try requireCurrent(account)
                guard dependencies.canUseNetwork() else { return nil }
                let page = try await dependencies.page(cursor, account)
                try requireCurrent(account)
                for candidate in page.candidates {
                    try requireCurrent(account)
                    guard dependencies.canUseNetwork() else { return nil }
                    if let due = candidate.due, due > dependencies.now() { include(due); continue }
                    do {
                        let ready = try await dependencies.prepareFunding(candidate, account)
                        try requireCurrent(account)
                        if !ready { include(dependencies.now().addingTimeInterval(30)); continue }
                    } catch {
                        try requireCurrent(account)
                        include(dependencies.now().addingTimeInterval(30)); continue
                    }
                    if !OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: candidate.attemptCount) {
                        _ = try await dependencies.postpone(candidate, dependencies.now(), account)
                        try requireCurrent(account)
                        continue
                    }
                    var claimed: Candidate?
                    do {
                        let claim = try await dependencies.claim(candidate, dependencies.now(), account)
                        claimed = claim
                        try requireCurrent(account)
                        guard dependencies.canUseNetwork() else { throw SharedMediaStorageFailure.unavailable }
                        if claim.dispatch == nil { try await dependencies.execute(claim, account) } else {
                            try await dependencies.recover(claim, account)
                        }
                        try requireCurrent(account)
                    } catch {
                        try requireCurrent(account)
                        let due = dependencies.now().addingTimeInterval(OfflineQueueRetryPolicy.delay(
                            forAttempt: claimed?.attemptCount ?? candidate.attemptCount))
                        if let claimed {
                            // A lost claim/result save is never guessed. Failed
                            // postponement leaves discovery to reread durable state.
                            do {
                                if try await dependencies.postpone(claimed, due, account) { include(due) }
                            } catch { try requireCurrent(account); include(due) }
                        } else { include(due) }
                    }
                }
                cursor = page.nextCursor
                if cursor == nil { let next = sweepDeadline; sweepDeadline = nil; return next }
                await Task.yield()
            }
            return min(sweepDeadline ?? .distantFuture, dependencies.now().addingTimeInterval(1))
        } catch {
            guard !Task.isCancelled, !isClosed, dependencies.isCurrent() else { return nil }
            do { try account.validate() } catch { return nil }
            include(dependencies.now().addingTimeInterval(5))
            return sweepDeadline
        }
    }

    private func include(_ due: Date) { sweepDeadline = min(sweepDeadline ?? due, due) }

    private func schedule(_ next: Date) {
        let id = UUID(); wakeID = id
        wake = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await dependencies.sleep(max(1, next.timeIntervalSince(dependencies.now()))) } catch { return }
            guard !Task.isCancelled, !isClosed, dependencies.isCurrent(), wakeID == id else { return }
            wake = nil; wakeID = nil
            await drain()
        }
    }
}
