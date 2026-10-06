import Foundation
import Observation

/// One displayed review ticket. No task, idle lease or timer owns admission.
@MainActor @Observable
final class IdentificationHistoryReviewModel {
    let ticket: ObservationAnalysisReviewTicket
    private(set) var request: ObservationAnalysisReviewRequest?
    private(set) var status: ObservationAnalysisReviewStatus?
    private(set) var undoOperation: UUID?
    private(set) var message: String?
    private(set) var terminalMessage: String?
    private(set) var canRetrySave = false
    private(set) var blocked = true
    private(set) var isClosed = false
    private var observedOperation: UUID?
    private let access: IdentificationHistoryReviewAccess
    private let isCurrent: () -> Bool

    init(ticket: ObservationAnalysisReviewTicket, access: IdentificationHistoryReviewAccess, isCurrent: @escaping () -> Bool) {
        self.ticket = ticket; self.access = access; self.isCurrent = isCurrent
        refresh()
    }
    var canSubmit: Bool { !isClosed && !blocked && request == nil && terminalMessage == nil }
    var hasUnresolvedRequest: Bool { request != nil && terminalMessage == nil }

    /// Freeze and persist synchronously in the button callback, before any wake.
    func submit(_ decision: ObservationAnalysisReviewRequest.Decision) {
        guard current(), canSubmit else { return }
        do {
            guard try access.pending() == nil else { refresh(); return }
            if case let .undo(rejectionID) = decision {
                guard try access.undo(ticket) == rejectionID else { throw ObservationHistoryError.resultConflict }
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
        do {
            try access.stage(request, ticket)
            guard current() else { return }
            observedOperation = request.operationID
            message = nil
            access.wake()
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
            if !blocked { undoOperation = try access.undo(ticket) }
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
        isClosed = true; blocked = true; canRetrySave = false
        request = nil; observedOperation = nil; status = nil; undoOperation = nil; message = nil; terminalMessage = nil
    }
}
