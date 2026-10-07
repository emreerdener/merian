import Foundation
import Observation

/// One displayed review ticket. No task, idle lease or timer owns admission.
@MainActor @Observable
final class IdentificationHistoryReviewModel {
    let ticket: ObservationAnalysisReviewTicket
    private(set) var request: ObservationAnalysisReviewRequest?
    private(set) var status: ObservationAnalysisReviewStatus?
    private(set) var undoOperation: UUID?
    private(set) var confirmationUndo: ObservationConfirmationUndoEligibility?
    private(set) var confirmationUndoMessage: String?
    private var lookupTask: Task<Void, Never>?
    private var opened = false
    private(set) var message: String?
    private(set) var terminalMessage: String?
    private(set) var canRetrySave = false
    private(set) var blocked = true
    private(set) var isClosed = false
    private var observedOperation: UUID?
    private let access: IdentificationHistoryReviewAccess
    private let isCurrent: () -> Bool
    private let canStartReview: () -> Bool

    init(ticket: ObservationAnalysisReviewTicket, access: IdentificationHistoryReviewAccess, isCurrent: @escaping () -> Bool,
         canStartReview: (() -> Bool)? = nil) {
        self.ticket = ticket; self.access = access; self.isCurrent = isCurrent
        self.canStartReview = canStartReview ?? isCurrent
        refresh()
    }
    /// Explicit presentation opportunity, never called from status/epoch refresh.
    func open() {
        guard current(), !opened else { return }
        opened = true
        access.wake()
        guard canSubmit else { return }
        guard ticket.confirmationAction != nil else {
            if ticket.reviewState == .aiConfirmed || ticket.reviewState == .userOverridden {
                confirmationUndoMessage = "This identification’s current authority cannot be undone as your confirmation."
            }
            return
        }
        guard let prepare = access.prepareConfirmationUndo else {
            confirmationUndoMessage = "Undo confirmation is unavailable in this presentation."
            return
        }
        confirmationUndoMessage = "Checking confirmation record…"
        lookupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let resolution = try await prepare(self.ticket)
                try Task.checkCancellation()
                guard self.current(), self.canStartReview(), self.canSubmit else { return }
                switch resolution {
                case let .available(eligibility): self.confirmationUndo = eligibility; self.confirmationUndoMessage = nil
                case let .unavailable(reason): self.confirmationUndoMessage = reason.message
                }
            } catch {
                guard !Task.isCancelled, self.current() else { return }
                self.confirmationUndoMessage = "Confirmation status is unavailable. Reopen this identification to try again."
            }
            self.lookupTask = nil
        }
    }
    var canSubmit: Bool { !isClosed && !blocked && request == nil && terminalMessage == nil }
    var hasUnresolvedRequest: Bool { request != nil && terminalMessage == nil }

    /// Freeze and persist synchronously in the button callback, before any wake.
    func submit(_ decision: ObservationAnalysisReviewRequest.Decision) {
        guard current(), canSubmit else { return }
        guard canStartReview() else {
            blocked = true
            message = "This identification changed. Open it again before making a new review."
            return
        }
        do {
            guard try access.pending() == nil else { refresh(); return }
            if case let .undo(rejectionID) = decision {
                guard try access.undo(ticket) == rejectionID else { throw ObservationHistoryError.resultConflict }
            }
            if case let .undoConfirmation(operation) = decision {
                guard confirmationUndo?.operationID == operation else { throw ObservationHistoryError.resultConflict }
            }
            request = try ticket.request(decision, operationID: UUID())
            persist()
        } catch {
            blocked = true
            message = "This review is unavailable. Refresh the preview before making a new choice."
        }
    }
    func retrySave() {
        guard current(), canRetrySave, request != nil else { return }
        persist()
    }
    private func persist() {
        guard let request, current() else { return }
        blocked = true; canRetrySave = false
        // Discovery is safe after a throw: only committed runnable work can execute.
        defer { if current() { access.wake() } }
        do {
            if case .undoConfirmation = request.decision {
                guard let confirmationUndo, let stage = access.stageConfirmationUndo else { throw ObservationHistoryError.unavailable }
                try stage(request, ticket, confirmationUndo)
            } else { try access.stage(request, ticket) }
            guard current() else { return }
            observedOperation = request.operationID
            message = nil
            refresh()
        } catch {
            guard current() else { return }
            // The save may have committed. Keep the exact request even when the
            // status read is nil or fails; a later retry must reuse its UUID.
            canRetrySave = true
            message = "This review has not been acknowledged locally. Retry saving the same choice."
            refresh()
        }
    }
    func refresh() {
        guard current() else { return }
        do {
            let pending = try access.pending()
            if observedOperation == nil, pending?.analysisID == ticket.analysisID { observedOperation = pending?.operationID }
            let operation = request?.operationID ?? observedOperation
            status = try operation.flatMap { try access.status(ticket, $0) }
            blocked = pending != nil || request != nil
            undoOperation = nil
            if let status {
                canRetrySave = false
                switch status.phase {
                case .pending: message = "Review pending. Your saved identification stays in place until the server acknowledges it."
                case .reconciling: message = "Review received. Refreshing identification authority."
                case .needsAttention: message = "This review needs attention. It will not retry automatically."
                case .complete(let outcome):
                    blocked = true
                    switch outcome {
                    case .applied: terminalMessage = "Review updated. Open the identification again to see its current review."
                    case .revisionConflict: terminalMessage = "This scan changed. Open a fresh preview before reviewing it."
                    case .notVerified: terminalMessage = "That species could not be verified. Open a fresh preview to make another choice."
                    }
                }
            } else if pending != nil {
                message = "Another review for this scan is pending. Resolve it before making another change."
            }
            if !blocked {
                if canStartReview() { undoOperation = try access.undo(ticket) } else {
                    blocked = true
                    message = "This identification changed. Open it again before making a new review."
                }
            }
        } catch {
            blocked = true; undoOperation = nil
            if !canRetrySave { message = "Review status is unavailable. Refresh this preview before making a change." }
        }
    }
    private func current() -> Bool {
        guard !isClosed, isCurrent() else { close(); return false }
        return true
    }
    func close() {
        lookupTask?.cancel(); lookupTask = nil; confirmationUndo = nil; confirmationUndoMessage = nil
        isClosed = true; blocked = true; canRetrySave = false
        request = nil; observedOperation = nil; status = nil; undoOperation = nil; message = nil; terminalMessage = nil
    }
}
