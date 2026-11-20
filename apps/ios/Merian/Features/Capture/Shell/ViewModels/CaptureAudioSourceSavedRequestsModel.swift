import Foundation
import Observation

/// Presentation only. Selection names a saved child; it never creates or replaces a request.
@MainActor @Observable
final class CaptureAudioSourceSavedRequestsModel {
    private(set) var rows: [ObservationAudioSourceSavedStatus.Summary] = []
    private(set) var next: ObservationAudioSourceSavedStatus.Cursor?
    private(set) var omittedCount = 0
    private(set) var selected: OfflineQueueWork.Reanalysis?
    private(set) var isBusy = false
    private(set) var isClosed = false
    private(set) var message: String?
    private let status: CaptureAudioSourceStatusAccess.Opened
    private let openResume: (OfflineQueueWork.Reanalysis) throws -> CaptureAudioSourceReanalysisAccess.Resumed
    private let isPresented: @MainActor () -> Bool
    private var generation = 0
    private var work: Task<Void, Never>?
    var isCurrent: Bool { !isClosed && status.isCurrent() && isPresented() }

    init(status: CaptureAudioSourceStatusAccess.Opened,
         openResume: @escaping (OfflineQueueWork.Reanalysis) throws -> CaptureAudioSourceReanalysisAccess.Resumed,
         isPresented: @escaping @MainActor () -> Bool) {
        self.status = status; self.openResume = openResume; self.isPresented = isPresented
    }

    func start(more: Bool = false) {
        guard work == nil, !isBusy, validate(), !more || next != nil else { return }
        let cursor = more ? next : nil, expected = generation
        // Old rows cannot remain actionable after refresh/page failure or while the next page loads.
        rows = []; next = nil; omittedCount = 0; selected = nil; message = nil; isBusy = true
        work = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { work = nil; isBusy = false } }
            do {
                let result = try await status.page(cursor, 20, { [weak self] in self?.generation == expected && self?.isCurrent == true })
                guard generation == expected, !Task.isCancelled, validate() else { return }
                rows = result.items; next = result.next; omittedCount = result.omittedCount
            } catch {
                guard generation == expected, !Task.isCancelled, validate() else { return }
                // Failed pages grant no actions or cursor; explicit refresh starts discovery again.
                message = "Saved requests could not be checked. Refresh to try again."
            }
        }
    }

    func select(_ row: ObservationAudioSourceSavedStatus.Summary) {
        guard work == nil, !isBusy, validate(), rows.contains(row) else { return }
        selected = row.identity; message = nil
    }

    func continueSelected() {
        guard work == nil, !isBusy, validate(), let identity = selected,
              rows.contains(where: { $0.identity == identity }) else { return }
        let resumed: CaptureAudioSourceReanalysisAccess.Resumed
        do {
            // Freeze exact four-ID target synchronously at the actual tap, before any Task.
            resumed = try openResume(identity)
        } catch {
            guard validate() else { return }
            message = "This saved request is unavailable. Its original identity has been kept."
            return
        }
        let expected = generation
        isBusy = true; message = nil
        work = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { work = nil; isBusy = false } }
            do {
                let admission = try await resumed.resume { [weak self] in self?.generation == expected && self?.isCurrent == true }
                guard generation == expected, !Task.isCancelled, validate() else { return }
                switch admission {
                case .started, .coalesced:
                    message = "This saved source request is being checked. Refresh for its latest status."
                case .unavailable:
                    message = "This saved request cannot continue right now. You can check the same request again later."
                }
            } catch {
                guard generation == expected, !Task.isCancelled, validate() else { return }
                message = "The outcome is not confirmed. The original saved request has been kept."
            }
        }
    }

    @discardableResult func validate() -> Bool {
        guard isCurrent else { close(); return false }
        return true
    }

    func close() {
        guard !isClosed else { return }
        generation += 1; isClosed = true; work?.cancel(); work = nil
        rows = []; next = nil; selected = nil; omittedCount = 0; message = nil; isBusy = false
        // Cancels only this presentation waiter, never queue-owned reads/preparation/execution or durable work.
    }
}
