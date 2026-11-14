import Foundation

/// A child presentation retains only a revocable handle, never the private request.
@MainActor
struct SavedReanalysisTicket {
    let resume: () -> Void
    let cancel: () -> Void
    static var unavailable: Self { .init(resume: {}, cancel: {}) }
}

typealias SavedReanalysisPreparation = @MainActor (String, UInt64?) -> SavedReanalysisTicket

/// One parent Insight owns preparation, child dismissal, and its cancellable waiter.
@MainActor
final class SavedReanalysisHandoff {
    private struct Pending {
        let id: UUID
        let request: SavedIdentificationReanalysisAccess.Request
        let isCurrent: () -> Bool
        let dispatch: (HistoricalReanalysisTarget) -> Void
        let failure: () -> Void
    }
    private var pending: Pending?
    private var task: Task<Void, Never>?
    var isBusy: Bool { pending != nil }

    func prepare(request: SavedIdentificationReanalysisAccess.Request,
                 isCurrent: @escaping () -> Bool,
                 dispatch: @escaping (HistoricalReanalysisTarget) -> Void,
                 failure: @escaping () -> Void) -> SavedReanalysisTicket {
        guard pending == nil, isCurrent() else { return .unavailable }
        let id = UUID()
        pending = .init(id: id, request: request, isCurrent: isCurrent, dispatch: dispatch, failure: failure)
        return .init(resume: { [weak self] in self?.resume(id) }, cancel: { [weak self] in self?.cancel(id) })
    }

    func cancel() {
        pending = nil
        task?.cancel()
        task = nil
    }

    private func cancel(_ id: UUID) {
        guard pending?.id == id else { return }
        cancel()
    }

    private func resume(_ id: UUID) {
        guard let entry = pending, entry.id == id, task == nil else { return }
        guard entry.isCurrent() else { cancel(id); return }
        task = Task { @MainActor [weak self] in
            defer {
                if self?.pending?.id == id { self?.pending = nil; self?.task = nil }
            }
            do {
                let action = try await entry.request.resolve()
                try Task.checkCancellation()
                guard self?.pending?.id == id, entry.isCurrent() else { return }
                entry.dispatch(try action.resolve())
            } catch {
                guard !Task.isCancelled, self?.pending?.id == id, entry.isCurrent() else { return }
                entry.failure()
            }
        }
    }
}
