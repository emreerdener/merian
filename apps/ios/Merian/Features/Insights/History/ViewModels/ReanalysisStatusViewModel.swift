import Foundation
import Observation

@MainActor @Observable
final class ReanalysisStatusViewModel {
    private(set) var rows: [ObservationReanalysisOperationStatus.Summary] = []
    private(set) var next: ObservationReanalysisOperationStatus.Cursor?
    private(set) var isBusy = false
    private(set) var isClosed = false
    private(set) var message: String?
    private let dependencies: ReanalysisStatusDependencies
    private let isPresented: () -> Bool
    private var generation = 0
    private var work: Task<Void, Never>?
    var isSessionCurrent: Bool { !isClosed && isPresented() && dependencies.isCurrent() }

    init(dependencies: ReanalysisStatusDependencies, isPresented: @escaping () -> Bool = { true }) {
        self.dependencies = dependencies; self.isPresented = isPresented
    }
    func start(more: Bool = false) {
        guard work == nil, !isBusy, !isClosed else { return }
        let expected = generation
        work = Task { [weak self] in
            await self?.load(more: more)
            if self?.generation == expected { self?.work = nil }
        }
    }
    func load(more: Bool = false) async {
        guard !isBusy, validate(), !more || next != nil else { return }
        let cursor = more ? next : nil, expected = generation
        isBusy = true; message = nil
        defer { if generation == expected { isBusy = false } }
        do {
            let result = try await dependencies.page(cursor)
            guard generation == expected, !Task.isCancelled, validate() else { return }
            rows = result.items; next = result.next
        } catch {
            guard generation == expected, !Task.isCancelled, validate() else { return }
            message = "Status is unavailable right now. Refresh to check again."
        }
    }
    @discardableResult func validate() -> Bool {
        guard isSessionCurrent else { close(); return false }
        do { try dependencies.validate(); return true } catch { close(); return false }
    }
    func close() {
        guard !isClosed else { return }
        generation += 1; isClosed = true; work?.cancel(); work = nil
        rows = []; next = nil; message = nil; isBusy = false
        dependencies.close()
    }
}
