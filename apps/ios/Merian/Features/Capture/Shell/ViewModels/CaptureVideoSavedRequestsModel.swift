import Foundation
import Observation

/// Presentation only. Selection names a saved child; it never creates or replaces a request.
@MainActor @Observable
final class CaptureVideoSavedRequestsModel {
    private(set) var rows: [ObservationVideoSavedStatus.Summary] = []
    private(set) var next: ObservationVideoSavedStatus.Cursor?
    private(set) var omittedCount = 0
    private(set) var selected: OfflineQueueWork.Reanalysis?
    private var isWorking = false
    private(set) var preview: CaptureSavedVideoPreviewModel?
    private(set) var recovery: AnalysisRecoveryCheckingModel?
    var isBusy: Bool { !isClosed && (isWorking || recovery?.isRunning == true) }
    var showsProgress: Bool { isWorking || recovery?.state == .checking }
    var recoveryMessage: String? { isClosed ? nil : recovery?.message }
    private(set) var isClosed = false
    private(set) var message: String?
    private let status: CaptureVideoStatusAccess.Opened
    private let openResume: (OfflineQueueWork.Reanalysis) throws -> CaptureVideoResumeAccess.Resumed
    private let isPresented: @MainActor () -> Bool
    private let makePreview: (Data, @escaping () -> Bool) throws -> CaptureSavedVideoPreviewModel
    private var previewGeneration = 0
    private var isVisible = true
    private var generation = 0
    private var work: Task<Void, Never>?
    var isCurrent: Bool { !isClosed && status.isCurrent() && isPresented() }

    init(status: CaptureVideoStatusAccess.Opened,
         openResume: @escaping (OfflineQueueWork.Reanalysis) throws -> CaptureVideoResumeAccess.Resumed,
         isPresented: @escaping @MainActor () -> Bool,
         makePreview: ((Data, @escaping () -> Bool) throws -> CaptureSavedVideoPreviewModel)? = nil) {
        self.status = status; self.openResume = openResume; self.isPresented = isPresented
        self.makePreview = makePreview ?? { try CaptureSavedVideoPreviewModel(bytes: $0, validate: $1) }
    }

    func start(more: Bool = false) {
        guard work == nil, !isBusy, validate(), !more || next != nil else { return }
        let cursor = more ? next : nil, expected = generation
        closePreview()
        // Old rows cannot remain actionable after refresh/page failure or while the next page loads.
        rows = []; next = nil; omittedCount = 0; selected = nil; message = nil; isWorking = true
        work = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { work = nil; isWorking = false } }
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

    func select(_ row: ObservationVideoSavedStatus.Summary) {
        guard work == nil, !isBusy, validate(), rows.contains(row) else { return }
        recovery?.close(); recovery = nil
        closePreview()
        selected = row.identity; message = nil
    }

    func continueSelected() {
        guard work == nil, !isBusy, isVisible, validate(), let identity = selected,
              rows.contains(where: { $0.identity == identity }) else { return }
        closePreview()
        let resumed: CaptureVideoResumeAccess.Resumed
        do {
            // Freeze exact four-ID target synchronously at the actual tap, before any Task.
            resumed = try openResume(identity)
        } catch {
            guard validate() else { return }
            message = "This saved request is unavailable. Its original identity has been kept."
            return
        }
        if let row = rows.first(where: { $0.identity == identity }), row.phase == .outcomeRecovery {
            guard let access = resumed.recovery else {
                message = "The original result cannot be checked right now."
                return
            }
            message = nil
            recovery = AnalysisRecoveryCheckingModel(access: access, didFinish: { [weak self] in
                guard let self, validate(), recovery?.state == .recovered else { return }
                start()
            })
            recovery?.check()
            return
        }
        let expected = generation
        isWorking = true; message = nil
        work = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { work = nil; isWorking = false } }
            do {
                let admission = try await resumed.resume { [weak self] in self?.generation == expected && self?.isCurrent == true }
                guard generation == expected, !Task.isCancelled, validate() else { return }
                switch admission {
                case .started, .coalesced:
                    message = "This saved video request is being checked. Refresh for its latest status."
                case .unavailable:
                    message = "This saved request cannot continue right now. You can check the same request again later."
                }
            } catch {
                guard generation == expected, !Task.isCancelled, validate() else { return }
                message = "The outcome is not confirmed. The original saved request has been kept."
            }
        }
    }

    func previewSelected() {
        guard work == nil, !isBusy, isVisible, validate(), let identity = selected,
              rows.contains(where: { $0.identity == identity }) else { return }
        closePreview()
        let read: (@escaping @MainActor @Sendable () -> Bool) async throws -> CaptureVideoResumeAccess.Preview
        do {
            guard let capability = try openResume(identity).preview else { throw ObservationHistoryError.unavailable }
            read = capability
        } catch {
            message = "The saved video is unavailable. Your request has been kept."
            return
        }
        let expected = generation, expectedPreview = previewGeneration
        isWorking = true; message = nil
        work = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { work = nil; isWorking = false } }
            do {
                let saved = try await read { [weak self] in
                    self?.generation == expected && self?.previewGeneration == expectedPreview &&
                        self?.isVisible == true && self?.selected == identity && self?.isCurrent == true
                }
                guard !Task.isCancelled, generation == expected, previewGeneration == expectedPreview,
                      isVisible, selected == identity, validate() else { return }
                try saved.validate()
                let validateSaved = saved.validate
                let player = try makePreview(saved.bytes, { [weak self] in
                    guard let self else { return false }
                    guard generation == expected, previewGeneration == expectedPreview, isVisible, selected == identity, validate() else { return false }
                    do { try validateSaved(); return true } catch { return false }
                })
                preview = player
                await player.load()
                guard !Task.isCancelled, generation == expected, validate() else { player.close(); return }
            } catch {
                guard generation == expected, previewGeneration == expectedPreview, !Task.isCancelled, validate() else { return }
                message = "The saved video is unavailable. Your request has been kept."
            }
        }
    }

    func closePreview() { previewGeneration += 1; preview?.close(); preview = nil }

    @discardableResult func validate() -> Bool {
        guard isCurrent else { close(); return false }
        do { try status.validate(); return true } catch { close(); return false }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible { closePreview() }
        if visible, !validate() { return }
        recovery?.setVisible(visible)
    }

    func close() {
        guard !isClosed else { return }
        recovery?.close()
        closePreview()
        generation += 1; isClosed = true; work?.cancel(); work = nil
        rows = []; next = nil; selected = nil; omittedCount = 0; message = nil; isWorking = false
        // Cancels only this presentation waiter, never queue-owned reads/preparation/execution or durable work.
    }
}
