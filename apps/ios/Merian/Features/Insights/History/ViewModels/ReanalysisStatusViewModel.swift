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
    private var libraryRefreshPending = false
    private var retirementRequest: (child: UUID, operation: UUID)?
    var allowsRetirement: Bool { dependencies.retire != nil }
    var deliveryGeneration: UInt64 { dependencies.generation() }
    var isSessionCurrent: Bool { !isClosed && isPresented() && dependencies.isCurrent() }

    init(dependencies: ReanalysisStatusDependencies, isPresented: @escaping () -> Bool = { true }) {
        self.dependencies = dependencies; self.isPresented = isPresented
    }
    func start(more: Bool = false) {
        guard work == nil, !isBusy, !isClosed else { return }
        let expected = generation
        work = Task { [weak self] in
            await self?.load(more: more)
            if self?.generation == expected {
                self?.work = nil
                self?.refreshLibraryWhenIdle()
            }
        }
    }
    func load(more: Bool = false) async {
        guard !isBusy, validate(), !more || next != nil else { return }
        let cursor = more ? next : nil, expected = generation
        isBusy = true; message = nil
        defer { if generation == expected { isBusy = false; refreshLibraryWhenIdle() } }
        do {
            let result = try await dependencies.page(cursor)
            guard generation == expected, !Task.isCancelled, validate() else { return }
            rows = result.items; next = result.next
        } catch {
            guard generation == expected, !Task.isCancelled, validate() else { return }
            message = "Status is unavailable right now. Refresh to check again."
        }
    }
    func requestRetirement(_ row: ObservationReanalysisOperationStatus.Summary) {
        guard work == nil, !isBusy, validate(), rows.contains(row), row.retirement != nil,
              let retire = dependencies.retire else { return }
        if let retained = retirementRequest, retained.child != row.id {
            message = "Finish checking the previous request before choosing another."
            return
        }
        // Freeze exactly once at the final tap, before scheduling asynchronous work.
        let operation = retirementRequest?.operation ?? UUID()
        retirementRequest = (row.id, operation)
        let expected = generation
        isBusy = true; message = nil
        work = Task { [weak self] in
            do {
                let result = try await retire(row, operation)
                guard let self, generation == expected, !Task.isCancelled, validate() else { return }
                work = nil; isBusy = false
                if result == .saved {
                    retirementRequest = nil
                    start()
                } else {
                    message = "This request cannot be safely stopped. Its original outcome is still being preserved."
                }
            } catch {
                guard let self, generation == expected, !Task.isCancelled, validate() else { return }
                work = nil; isBusy = false
                message = "The stop request could not be confirmed. Try checking the same request again."
            }
        }
    }

    func refreshForLibraryChange() {
        guard validate() else { return }
        libraryRefreshPending = true
        refreshLibraryWhenIdle()
    }
    private func refreshLibraryWhenIdle() {
        guard libraryRefreshPending, work == nil, !isBusy, !isClosed else { return }
        libraryRefreshPending = false
        start()
    }
    @discardableResult func validate() -> Bool {
        guard isSessionCurrent else { close(); return false }
        do { try dependencies.validate(); return true } catch { close(); return false }
    }
    func close() {
        guard !isClosed else { return }
        generation += 1; isClosed = true; work?.cancel(); work = nil
        rows = []; next = nil; message = nil; isBusy = false; retirementRequest = nil
        dependencies.close()
    }
}
