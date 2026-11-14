import Foundation
import Observation

@MainActor @Observable
final class ReanalysisStatusViewModel {
    private(set) var rows: [ObservationReanalysisOperationStatus.Summary] = []
    private(set) var next: ObservationReanalysisOperationStatus.Cursor?
    private var isWorking = false
    private(set) var recovery: AnalysisRecoveryCheckingModel?
    private(set) var photo: ReanalysisSavedPhotoAccess.Preview?
    private(set) var photoRow: ObservationReanalysisOperationStatus.Summary?
    var isBusy: Bool { !isClosed && (isWorking || recovery?.isRunning == true) }
    var recoveryMessage: String? { isClosed ? nil : recovery?.message }
    var showsProgress: Bool { isWorking || recovery?.state == .checking }
    private(set) var isClosed = false
    private(set) var message: String?
    private let dependencies: ReanalysisStatusDependencies
    private let isPresented: () -> Bool
    private var generation = 0
    private var photoGeneration = 0
    private var isVisible = true
    private var work: Task<Void, Never>?
    private var libraryRefreshPending = false
    private var retirementRequest: (child: UUID, operation: UUID)?
    var allowsOutcomeRecovery: Bool { dependencies.recovery != nil }
    var allowsPhotoPreview: Bool { dependencies.photo != nil }
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
        closePhoto()
        isWorking = true; message = nil
        defer { if generation == expected { isWorking = false; refreshLibraryWhenIdle() } }
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
        closePhoto()
        if let retained = retirementRequest, retained.child != row.id {
            message = "Finish checking the previous request before choosing another."
            return
        }
        // Freeze exactly once at the final tap, before scheduling asynchronous work.
        let operation = retirementRequest?.operation ?? UUID()
        retirementRequest = (row.id, operation)
        let expected = generation
        isWorking = true; message = nil
        work = Task { [weak self] in
            do {
                let result = try await retire(row, operation)
                guard let self, generation == expected, !Task.isCancelled, validate() else { return }
                work = nil; isWorking = false
                if result == .saved {
                    retirementRequest = nil
                    start()
                } else {
                    message = "This request cannot be safely stopped. Its original outcome is still being preserved."
                    refreshLibraryWhenIdle()
                }
            } catch {
                guard let self, generation == expected, !Task.isCancelled, validate() else { return }
                work = nil; isWorking = false
                message = "The stop request could not be confirmed. Try checking the same request again."
                refreshLibraryWhenIdle()
            }
        }
    }

    func checkOutcome(_ row: ObservationReanalysisOperationStatus.Summary) {
        guard work == nil, !isBusy, validate(), rows.contains(row), row.canCheckOutcome,
              let open = dependencies.recovery else { return }
        closePhoto()
        do {
            let access = try open(row)
            message = nil
            recovery = AnalysisRecoveryCheckingModel(access: access, didFinish: { [weak self] in
                guard let self, validate() else { return }
                if recovery?.state == .recovered { libraryRefreshPending = true }
                refreshLibraryWhenIdle()
            })
            recovery?.check()
        } catch { message = "The original result cannot be checked right now." }
    }

    func viewPhoto(_ row: ObservationReanalysisOperationStatus.Summary, index: Int = 0) {
        guard work == nil, !isBusy, isVisible, validate(), rows.contains(row), let read = dependencies.photo else { return }
        closePhoto()
        let expected = generation, expectedPhoto = photoGeneration
        isWorking = true; message = nil
        work = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { work = nil; isWorking = false; refreshLibraryWhenIdle() } }
            do {
                let result = try await read(row, index, { [weak self] in
                    self?.generation == expected && self?.photoGeneration == expectedPhoto &&
                        self?.isVisible == true && self?.isSessionCurrent == true
                })
                guard !Task.isCancelled, generation == expected, photoGeneration == expectedPhoto,
                      isVisible, validate(), rows.contains(row) else { return }
                try result.validate()
                photo = result; photoRow = row
            } catch {
                guard !Task.isCancelled, generation == expected, photoGeneration == expectedPhoto, validate() else { return }
                message = "The saved photos are unavailable. Your request has been kept."
            }
        }
    }

    func closePhoto() { photoGeneration += 1; photo = nil; photoRow = nil }
    func checkPhotoScope() {
        guard validate(), let photo else { return }
        do { try photo.validate() } catch {
            closePhoto(); message = "The saved photos are unavailable. Your request has been kept."
        }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible { closePhoto() }
        if visible, !validate() { return }
        recovery?.setVisible(visible)
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
        recovery?.close()
        closePhoto()
        generation += 1; isClosed = true; work?.cancel(); work = nil
        rows = []; next = nil; message = nil; isWorking = false; retirementRequest = nil
        dependencies.close()
    }
}
