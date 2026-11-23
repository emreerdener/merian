import Foundation
import Observation
import UIKit
#if MERIAN_HISTORY_LOCAL_DIAGNOSTICS
import OSLog
#endif

@MainActor @Observable
final class IdentificationHistoryViewModel {
    enum CardAction { case use, confirm, reject, review, candidates, community, reanalyze }
    enum Command { case newest, older, preview(UUID), restore, undo, retry, reanalyze }
    private(set) var rows: [IdentificationHistoryRow] = []
    private(set) var pinnedCurrent: IdentificationHistoryRow?
    private var cardPresentation = false
    private var needsCurrentCard = false
    private(set) var thumbnails: [UUID: UIImage] = [:]
    private var thumbnailWork: Task<Void, Never>?
    private(set) var thumbnailGeneration = 0
    private var thumbnailRunningGeneration: Int?
    private var pendingThumbnailIDs: Set<UUID> = []
    private var attemptedThumbnailIDs: Set<UUID> = []
    var cardRows: [IdentificationHistoryRow] {
        let current = rows.first { $0.id == selected } ?? pinnedCurrent
        return (current.map { [$0] } ?? []) + rows.filter { $0.id != selected }
    }
    var canChangeCardScope: Bool {
        !isBusy && !isClosed && !pending && review?.hasUnresolvedRequest != true && publication == nil
    }

    func openCards() {
        cardPresentation = true
        if rows.isEmpty { start(.newest) } else { needsCurrentCard = true; finishUpdatesWhenIdle() }
    }

    /// Resolve the exact card before invoking existing selection/review owners.
    /// Merely opening a menu neither fetches authority nor selects a version.
    func performCardAction(_ action: CardAction, id: UUID) async -> CardAction? {
        guard work == nil, canChangeCardScope, validate(), allowChoice(),
              cardRows.contains(where: { $0.id == id }) else { return nil }
        let expected = generation
        needsCurrentCard = false
        await perform(.preview(id))
        guard accepts(expected), detail?.row.id == id, !isBusy, !pending else { return nil }
        switch action {
        case .use: await perform(.restore)
        case .confirm:
            guard let review, review.canSubmit else { return nil }
            if review.ticket.canConfirmPrimary { review.submit(.confirmPrimary) } else if review.ticket.canConfirmName { return .review }
        case .reject:
            guard let review, review.canSubmit, review.ticket.canReject else { return nil }
            review.submit(.reject)
        case .review: return review == nil ? nil : .review
        case .candidates: return review?.ticket.candidateChoices.isEmpty == false ? .candidates : nil
        case .community:
            askCommunity()
            return publication == nil ? nil : .community
        case .reanalyze: await perform(.reanalyze)
        }
        return nil
    }

    func returnToCards() {
        guard review?.hasUnresolvedRequest != true else { return }
        back()
        needsCurrentCard = true
        finishUpdatesWhenIdle()
    }
    private(set) var detail: IdentificationHistoryDetail? {
        didSet { review?.close(); review = nil; publication?.close(); publication = nil }
    }
    private(set) var review: IdentificationHistoryReviewModel?
    private(set) var publication: IdentificationPublicationModel?
    private let publicationContinuation: PublicationConsentContinuation?
    var canAskCommunity: Bool { dependencies.publicationConsent != nil && detail?.reviewTicket.map { $0.supportsPhotoPublicationFormat && publicationContinuation?.matches($0) == true } == true && !pending && !isBusy && !isClosed }
    var reviewDeliveryGeneration: UInt64 { dependencies.review?.generation() ?? 0 }
    private(set) var photo: UIImage?
    private(set) var selected: UUID?
    private(set) var pending = false
    private(set) var isBusy = false
    private(set) var isClosed = false
    private(set) var message: String?
    private(set) var nextBeforeOrdinal: Int?
    private(set) var showingOlder = false
    private(set) var undoOperation: UUID?
    private var undoDeadline: Date?
    private var generation = 0
    private var acknowledgedRevision: Int?
    private var photoGeneration = 0
    private var work: Task<Void, Never>?
    private var libraryRefreshPending = false
    private var admissionNotificationPending = false
    private var reanalysisAction: IdentificationHistoryReanalysisAction?
    private let handoffReanalysis: ((IdentificationHistoryReanalysisAction) -> Bool)?
    var canReanalyze: Bool { reanalysisAction != nil && handoffReanalysis != nil && !pending && !isBusy && !isClosed }
    private let dependencies: IdentificationHistoryDependencies
    private let isPresented: () -> Bool
    private let didAdmit: () -> Void

    init(dependencies: IdentificationHistoryDependencies, isPresented: @escaping () -> Bool = { true }, didAdmit: @escaping () -> Void = {},
         handoffReanalysis: ((IdentificationHistoryReanalysisAction) -> Bool)? = nil,
         publicationContinuation: PublicationConsentContinuation? = nil) {
        self.publicationContinuation = publicationContinuation
        self.handoffReanalysis = handoffReanalysis
        self.dependencies = dependencies; self.isPresented = isPresented; self.didAdmit = didAdmit
    }
    func start(_ command: Command) {
        guard work == nil, !isBusy, !isClosed else { return }
        let expected = generation
        work = Task { [weak self] in
            await self?.perform(command)
            if self?.generation == expected {
                self?.work = nil
                self?.finishUpdatesWhenIdle()
            }
        }
    }
    func perform(_ command: Command) async {
        guard !isBusy, validate() else { return }
        isBusy = true; message = nil
        let expected = generation
        defer { if generation == expected { isBusy = false; finishUpdatesWhenIdle() } }
        do {
            switch command {
            case .newest, .older:
                let before: Int?
                if case .older = command { guard let nextBeforeOrdinal else { return }; before = nextBeforeOrdinal } else { before = nil }
                try await loadPage(before: before, expected: expected)
            case .preview(let id):
                guard rows.contains(where: { $0.id == id }) || (cardPresentation && pinnedCurrent?.id == id && selected == id) else { return }
                let baseline = try dependencies.context()
                let result = try await dependencies.preview(id)
                guard accepts(expected), result.row.id == id else { return }
                guard try dependencies.context() == baseline else {
                    throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
                }
                detail = result; photo = nil
                if let ticket = result.reviewTicket, let access = dependencies.review {
                    review = IdentificationHistoryReviewModel(ticket: ticket, access: access, isCurrent: { [weak self] in
                        guard let self else { return false }
                        return self.generation == expected && self.detail?.reviewTicket == ticket && self.isSessionCurrent
                    })
                }
                reanalysisAction = handoffReanalysis == nil ? nil : try? dependencies.reanalysis?(id, baseline)
            case .reanalyze:
                guard allowChoice() else { return }
                guard detail != nil, !pending, let action = reanalysisAction, let handoffReanalysis else { return }
                _ = try action.resolve()
                guard accepts(expected), detail != nil else { return }
                if handoffReanalysis(action) { reanalysisAction = nil }
            case .restore:
                guard allowChoice() else { return }
                guard let detail, detail.canRestore, !pending, detail.row.id != selected else { return }
                try dependencies.prepare(detail.row.id)
                pending = true; undoOperation = nil
                try await send(expected)
            case .undo:
                guard allowChoice() else { return }
                guard let operation = undoOperation, !pending else { return }
                try dependencies.prepareUndo(operation)
                pending = true; undoOperation = nil
                try await send(expected)
            case .retry:
                guard pending else { return }
                try await send(expected)
            }
        } catch {
            guard accepts(expected) else { return }
            if let state = try? dependencies.context() { apply(state) }
            if error is CancellationError { return }
            if pending {
                message = "Change pending. Your current identification stays in place until the server acknowledges it. Retry when connected."
            } else if error is ObservationHistoryPreviewService.AdmissionError || error is ObservationHistorySelectionIntent.Failure {
                detail = nil; photo = nil; reanalysisAction = nil; undoOperation = nil
                message = "This scan changed. Refresh history before choosing an identification."
            } else { message = "History is unavailable right now. Your saved identifications have not been removed. Try again." }
        }
    }
    /// Capture the admitted detail synchronously at the actual user tap.
    func askCommunity() {
        guard validate(), canAskCommunity, publication == nil, allowChoice(),
              let ticket = detail?.reviewTicket, let access = dependencies.publicationConsent,
              let publicationContinuation, publicationContinuation.matches(ticket) else { return }
        let expected = generation
        let model = IdentificationPublicationModel(ticket: ticket, access: access, continuation: publicationContinuation,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return self.generation == expected && self.detail?.reviewTicket == ticket && self.isSessionCurrent
            }, photo: dependencies.photo)
        publication = model
        model.startRecovery()
    }
    func prepareCandidateReview() -> AnalysisCandidateReviewModel? {
        guard validate(), !pending, !isBusy, allowChoice(), let review,
              review.canSubmit, !review.ticket.candidateChoices.isEmpty,
              detail?.reviewTicket == review.ticket else { return nil }
        let expected = generation
        let ticket = review.ticket
        return AnalysisCandidateReviewModel(review: review, isCurrent: { [weak self, weak review] in
            guard let self, let review else { return false }
            return self.generation == expected && self.review === review &&
                self.detail?.reviewTicket == ticket && self.isSessionCurrent
        }, loadPhoto: dependencies.photo, confirm: { [weak review] reference in
            review?.submit(.confirmCandidate(reference))
        })
    }
    private func allowChoice() -> Bool {
        do {
            guard review?.hasUnresolvedRequest != true, try dependencies.pendingReview() == nil else {
                message = "A review for this scan is unresolved. Resolve it before changing or reanalyzing an identification."
                return false
            }
            return true
        } catch {
            message = "Review status is unavailable. Refresh history before making a change."
            return false
        }
    }
    func refreshForLibraryChange() {
        guard validate() else { return }
        libraryRefreshPending = true
        refreshLibraryWhenIdle()
    }
    private func refreshLibraryWhenIdle() {
        if cardPresentation, libraryRefreshPending, work == nil, !isBusy, !pending,
           detail?.row.id == selected, review?.hasUnresolvedRequest != true, publication == nil {
            detail = nil; photo = nil; reanalysisAction = nil
        }
        guard libraryRefreshPending, work == nil, !isBusy, !isClosed,
              detail == nil, review == nil, publication == nil, !pending else { return }
        libraryRefreshPending = false
        start(.newest)
    }
    private func finishUpdatesWhenIdle() {
        notifyAdmissionWhenIdle()
        refreshLibraryWhenIdle()
        if cardPresentation, needsCurrentCard, work == nil, !isBusy, !isClosed, !pending,
           detail == nil, let selected, cardRows.contains(where: { $0.id == selected }) {
            needsCurrentCard = false
            start(.preview(selected))
        }
    }
    private func notifyAdmissionWhenIdle() {
        guard work == nil, !isBusy, !isClosed else { return }
        if admissionNotificationPending {
            admissionNotificationPending = false
            guard isSessionCurrent else { close(); return }
            // Parent refresh reloads observable Insight/Inference state. Deliver
            // only after this command releases its busy/task ownership, including
            // after a failed page read. Never reenter selection acknowledgement.
            traceSelection("before-parent-refresh")
            didAdmit()
            traceSelection("after-parent-refresh")
        }
    }
    func refreshReview() {
        let previousRevision = acknowledgedRevision
        guard validate() else { return }
        review?.refresh()
        publication?.refreshStatus()
        let terminal = review?.terminalMessage
        if let terminal {
            detail = nil; photo = nil; reanalysisAction = nil
            rows = []; pinnedCurrent = nil; nextBeforeOrdinal = nil; showingOlder = false
            message = terminal
        }
        // Validation may have invalidated the old review ticket before its
        // terminal message can be read. Either signal needs one fresh page.
        if previousRevision != acknowledgedRevision || terminal != nil {
            libraryRefreshPending = true
            finishUpdatesWhenIdle()
        }
    }
    private func loadPage(before: Int?, expected: Int) async throws {
        detail = nil; photo = nil; reanalysisAction = nil; photoGeneration += 1
        let page = try await dependencies.page(before)
        guard accepts(expected) else { return }
        guard page.context == (try dependencies.context()) else {
            throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
        }
        guard page.rows.count <= 20, Set(page.rows.map(\.id)).count == page.rows.count else {
            throw ObservationHistoryError.invalidPage
        }
        apply(page.context)
        rows = page.rows; detail = nil; photo = nil; reanalysisAction = nil
        nextBeforeOrdinal = page.nextBeforeOrdinal; showingOlder = before != nil
        pinnedCurrent = nil
        if cardPresentation, !rows.contains(where: { $0.id == page.context.selected }) {
            let current = try await dependencies.preview(page.context.selected)
            guard accepts(expected), current.row.id == page.context.selected,
                  try dependencies.context() == page.context else { throw ObservationHistoryPreviewService.AdmissionError.refreshRequired }
            pinnedCurrent = current.row
        }
        needsCurrentCard = cardPresentation
        if cardPresentation { loadCardThumbnails() }
    }
    private func send(_ expected: Int) async throws {
        traceSelection("before-send")
        let outcome = try await dependencies.sendPending()
        traceSelection("after-send")
        guard accepts(expected) else { return }
        let state = try dependencies.context()
        traceSelection("before-apply")
        apply(state); detail = nil; photo = nil; reanalysisAction = nil
        traceSelection("after-apply")
        switch outcome {
        case .selected(let receipt):
            if state.undoOperation == UUID(uuidString: receipt.operation_id) {
                undoOperation = state.undoOperation; undoDeadline = dependencies.now().addingTimeInterval(15)
                message = "Identification updated. Other history entries are kept."
            } else { message = "History refreshed. A newer choice is already current." }
        case .rejected:
            undoOperation = nil; undoDeadline = nil
            message = "This scan changed elsewhere. The current identification has been refreshed. Preview an entry to make a new choice."
        }
        // Acknowledgment changed the revision. Rebuild authority-bearing rows
        // from a current bounded page; a failed read cannot undo acknowledgment.
        do {
            traceSelection("before-acknowledged-page")
            try await loadPage(before: nil, expected: expected)
            traceSelection("after-acknowledged-page")
        } catch {
            guard accepts(expected) else { return }
            message = "Your change has been resolved. Refresh history to load the current entries."
        }
    }
    private func traceSelection(_ stage: String) {
#if MERIAN_HISTORY_LOCAL_DIAGNOSTICS
        Logger(subsystem: "app.merian.Merian", category: "HistoryLocalDiagnostics")
            .notice("selection-view stage=\(stage, privacy: .public)")
#endif
    }
    private func loadCardThumbnails() { clearCardThumbnails() }

    /// Admit visible rows only. Lazy view recreation cannot retry failed reads.
    func requestCardThumbnail(_ id: UUID) {
        guard cardPresentation, !isClosed, !attemptedThumbnailIDs.contains(id),
              thumbnails[id] == nil, cardRows.contains(where: { $0.id == id && $0.thumbnailMediaID != nil }),
              let load = dependencies.thumbnail else { return }
        pendingThumbnailIDs.insert(id)
        guard thumbnailRunningGeneration != thumbnailGeneration else { return }
        let previous = thumbnailWork
        let imageGeneration = thumbnailGeneration, expected = generation
        thumbnailRunningGeneration = imageGeneration
        thumbnailWork = Task { [weak self] in
            // Page changes cancel the preceding read, then join it before any
            // successor starts: only one original is held/decoded at a time.
            await previous?.value
            defer {
                if self?.thumbnailGeneration == imageGeneration { self?.thumbnailRunningGeneration = nil }
            }
            while !Task.isCancelled, let self, self.accepts(expected), self.thumbnailGeneration == imageGeneration,
                  let analysis = self.pendingThumbnailIDs.first {
                self.pendingThumbnailIDs.remove(analysis)
                guard let media = self.cardRows.first(where: { $0.id == analysis })?.thumbnailMediaID else { continue }
                self.attemptedThumbnailIDs.insert(analysis)
                guard let image = try? await load(analysis, media) else { continue }
                guard !Task.isCancelled, self.accepts(expected), self.thumbnailGeneration == imageGeneration,
                      self.cardRows.contains(where: { $0.id == analysis && $0.thumbnailMediaID == media }) else { return }
                self.thumbnails[analysis] = image
            }
        }
    }
    func hideCardThumbnail(_ id: UUID) { pendingThumbnailIDs.remove(id) }
    private func clearCardThumbnails() {
        thumbnailGeneration += 1; thumbnailWork?.cancel(); thumbnailRunningGeneration = nil
        thumbnails = [:]; pendingThumbnailIDs = []; attemptedThumbnailIDs = []
    }
    func loadPhoto(_ media: UUID) async {
        guard validate(), let detail, detail.photoIDs.contains(media) else { return }
        photoGeneration += 1
        let photoRequest = photoGeneration
        let expected = generation, analysis = detail.row.id
        photo = nil
        do {
            let image = try await dependencies.photo(analysis, media)
            guard accepts(expected), photoGeneration == photoRequest, self.detail?.row.id == analysis else { return }
            photo = image
        } catch {
            guard accepts(expected), photoGeneration == photoRequest, self.detail?.row.id == analysis else { return }
            message = "This evidence photo is unavailable right now. It has not been removed from history."
        }
    }
    func back() {
        guard !isBusy else { return }
        generation += 1; work?.cancel(); work = nil
        detail = nil; photo = nil; reanalysisAction = nil; isBusy = false; message = nil
        refreshLibraryWhenIdle()
    }
    // Observable account/presentation state invalidates the sheet without idle
    // database polling. Persistence is revalidated at each operation boundary.
    var isSessionCurrent: Bool { !isClosed && isPresented() && dependencies.isCurrent() }
    func expireUndo() async {
        guard let operation = undoOperation, let deadline = undoDeadline else { return }
        do {
            try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(dependencies.now()))))
        } catch {
            return
        }
        guard undoOperation == operation else { return }
        _ = validate()
    }
    @discardableResult func validate() -> Bool {
        guard !isClosed, isPresented(), dependencies.isCurrent() else { close(); return false }
        guard let state = try? dependencies.context() else { close(); return false }
        apply(state)
        if let undoDeadline, undoDeadline <= dependencies.now() { undoOperation = nil; self.undoDeadline = nil }
        notifyAdmissionWhenIdle()
        return !isClosed
    }
    private func accepts(_ expected: Int) -> Bool { generation == expected && !Task.isCancelled && validate() }
    private func apply(_ state: ObservationHistoryListingService.Context) {
        let changed = acknowledgedRevision != nil && (selected != state.selected || acknowledgedRevision != state.revision)
        selected = state.selected; pending = state.pendingOperation != nil
        if pending { review?.close(); review = nil }
        acknowledgedRevision = state.revision
        if let undoOperation, state.undoOperation != undoOperation { self.undoOperation = nil; undoDeadline = nil }
        if changed {
            // Titles can come from mutable community authority, not only result
            // evidence. No old row or restore control may outlive its revision.
            rows = []; pinnedCurrent = nil; detail = nil; photo = nil; reanalysisAction = nil; photoGeneration += 1
            nextBeforeOrdinal = nil; showingOlder = false
            clearCardThumbnails()
            message = "This scan changed. Refresh history before choosing an identification."
            admissionNotificationPending = true
        }
    }
    func close() {
        guard !isClosed else { return }
        isClosed = true; generation += 1; work?.cancel(); work = nil
        clearCardThumbnails()
        rows = []; pinnedCurrent = nil; needsCurrentCard = false; detail = nil; photo = nil; reanalysisAction = nil; selected = nil; undoOperation = nil; nextBeforeOrdinal = nil
        message = nil; isBusy = false; pending = false
        admissionNotificationPending = false; libraryRefreshPending = false
        dependencies.close()
    }
}
