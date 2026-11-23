import Foundation

/// Coalesces local settlement recovery. Its host registers `close` with the
/// native account lifetime before calling `drain`; no account lease survives a
/// retry sleep. Neither network reachability nor ordinary scan replay owns it.
@MainActor
final class SharedMediaCaptureFundingDrain {
    struct Dependencies {
        let begin: () throws -> InferenceCompletionAccountScope
        let page: (String?, InferenceCompletionAccountScope) async throws -> SharedMediaCaptureFundingRecovery.Page
        let recover: (SharedMediaCaptureFundingRecovery.Candidate, InferenceCompletionAccountScope) async throws -> Void
        let postpone: (SharedMediaCaptureFundingRecovery.Candidate, Date, InferenceCompletionAccountScope) async throws -> Void
        var isCurrent: () -> Bool = { true }
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
        guard !isClosed else { return }
        if let active { freshSweepRequested = true; _ = await active.value; return }
        wake?.cancel(); wake = nil; wakeID = nil
        let id = UUID()
        let task = Task { @MainActor [self] in await pass() }
        activeID = id; active = task
        let next = await task.value
        guard activeID == id else { return }
        active = nil; activeID = nil
        guard !isClosed else { return }
        if freshSweepRequested && cursor == nil {
            freshSweepRequested = false
            schedule(min(next ?? .distantFuture, dependencies.now().addingTimeInterval(1)))
        } else if let next { schedule(next) }
    }

    func close() async {
        isClosed = true
        let timer = wake, task = active
        wakeID = nil; wake = nil
        timer?.cancel(); task?.cancel()
        await timer?.value
        _ = await task?.value
        active = nil; activeID = nil
        cursor = nil; cursorOwner = nil; sweepDeadline = nil; freshSweepRequested = false
    }

    private func pass() async -> Date? {
        let account: InferenceCompletionAccountScope
        do { account = try dependencies.begin() } catch {
            guard !Task.isCancelled, !isClosed, dependencies.isCurrent() else { return nil }
            return dependencies.now().addingTimeInterval(5)
        }
        defer { account.finish() }
        if cursorOwner != account.ownerID {
            cursorOwner = account.ownerID; cursor = nil; sweepDeadline = nil
        }
        do {
            // Bound work per wake as well as each database page. Cursor and
            // earliest due time continue the same sweep on the next local wake.
            for _ in 0..<8 {
                try account.validate()
                let page = try await dependencies.page(cursor, account)
                try account.validate()
                for candidate in page.candidates {
                    try account.validate()
                    if let due = candidate.due, due > dependencies.now() {
                        include(due); continue
                    }
                    do {
                        try await dependencies.recover(candidate, account)
                        try account.validate()
                    } catch {
                        try account.validate()
                        let due = dependencies.now().addingTimeInterval(5)
                        include(due)
                        // A failed retry-date save cannot erase the original
                        // receipt. The local fallback still retries this sweep.
                        do { try await dependencies.postpone(candidate, due, account) } catch {
                            try account.validate()
                        }
                    }
                }
                cursor = page.nextCursor
                if cursor == nil {
                    let next = sweepDeadline; sweepDeadline = nil
                    return next
                }
                await Task.yield()
            }
            return min(sweepDeadline ?? .distantFuture, dependencies.now().addingTimeInterval(1))
        } catch {
            guard !Task.isCancelled, !isClosed else { return nil }
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
            guard !Task.isCancelled, !isClosed, wakeID == id else { return }
            wake = nil; wakeID = nil
            await drain()
        }
    }
}
