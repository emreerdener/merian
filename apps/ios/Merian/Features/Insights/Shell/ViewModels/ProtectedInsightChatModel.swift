import Foundation
import Observation

/// Parent presentation ownership preserves a save-uncertain request across sheet reopening.
@MainActor @Observable
final class ProtectedInsightChatContinuation {
    struct Candidate {
        let ticket: ProtectedInsightChatTicket
        let request: ProtectedInsightChatRequest
    }
    private(set) var candidate: Candidate?
    private var owner: UUID?
    private var observation: UUID?
    private var container: ObjectIdentifier?

    func bind(_ ticket: ProtectedInsightChatTicket, container: ObjectIdentifier) {
        if owner != ticket.ownerID || observation != ticket.observationID || self.container != container { clear() }
        owner = ticket.ownerID; observation = ticket.observationID; self.container = container
    }
    func retain(_ request: ProtectedInsightChatRequest, ticket: ProtectedInsightChatTicket) throws {
        guard candidate == nil, owner == ticket.ownerID, observation == ticket.observationID,
              request.observationID == ticket.observationID, request.selection == ticket.selection else { throw ObservationHistoryError.resultConflict }
        candidate = .init(ticket: ticket, request: request)
    }
    func acknowledge(_ intent: ProtectedInsightChatIntent) throws {
        guard let candidate, candidate.ticket.ownerID == intent.ownerID, candidate.request == intent.request else {
            throw ObservationHistoryError.resultConflict
        }
        self.candidate = nil
    }
    func clear() { candidate = nil; owner = nil; observation = nil; container = nil }
}

/// Local saved questions and immutable replies only. No legacy transcript, polling or idle lease.
@MainActor @Observable
final class ProtectedInsightChatModel {
    let id = UUID()
    let baseline: SelectedAnalysisReviewBaseline
    var text = ""
    private(set) var completed: [ProtectedInsightChatIntent] = []
    private(set) var unfinished: ProtectedInsightChatPersistence.PendingStatus?
    private(set) var next: UUID?
    private(set) var pageAfter: UUID?
    private(set) var message: String?
    private(set) var closed = false
    private(set) var hasStatus = false
    private(set) var deliveryRequested = false
    private(set) var canRecover = false
    private let session: ProtectedInsightChatAccess.Session
    private let continuation: ProtectedInsightChatContinuation
    private let presentationIsCurrent: () -> Bool
    private let makeID: () -> UUID
    var deliveryGeneration: UInt64 { session.generation() }
    var isCurrent: Bool { !closed && session.isCurrent() && presentationIsCurrent() }
    var canSend: Bool {
        isCurrent && hasStatus && unfinished == nil && continuation.candidate == nil
            && session.matchesDisplayedTicket() && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canRetrySave: Bool { isCurrent && continuation.candidate != nil }

    init(baseline: SelectedAnalysisReviewBaseline, session: ProtectedInsightChatAccess.Session,
         continuation: ProtectedInsightChatContinuation, presentationIsCurrent: @escaping () -> Bool,
         makeID: @escaping () -> UUID = UUID.init) {
        self.baseline = baseline; self.session = session; self.continuation = continuation
        self.presentationIsCurrent = presentationIsCurrent; self.makeID = makeID
    }

    func refresh(after: UUID? = nil) {
        guard isCurrent else { close(); return }
        do {
            let page = try session.status(after)
            guard isCurrent else { close(); return }
            completed = page.completed; unfinished = page.unfinished; next = page.nextAfterMessageID; pageAfter = after
            canRecover = try page.unfinished.map { pending in
                if pending.state == .held { return true }
                guard pending.state == .running else { return false }
                return try session.recoveryAllowed(pending.intent)
            } ?? false
            hasStatus = true; message = nil
            if let candidate = continuation.candidate {
                if let saved = page.unfinished?.intent, saved.request == candidate.request { try continuation.acknowledge(saved) } else if let saved = page.completed.first(where: { $0.request == candidate.request }) { try continuation.acknowledge(saved) }
            }
        } catch {
            hasStatus = false; completed = []; unfinished = nil; next = nil; canRecover = false
            message = "Saved chat could not be verified. Your question has not been replaced."
        }
    }

    /// Synchronous final tap: retain identity and persist before handing work to the queue.
    func send() {
        guard canSend else { return }
        do {
            let request = try session.ticket.request(conversationID: makeID(), clientMessageID: makeID(),
                normalizedText: text.trimmingCharacters(in: .whitespacesAndNewlines))
            try continuation.retain(request, ticket: session.ticket)
            saveCandidate(deliverAfterSave: true)
        } catch { message = "Enter a question of up to 600 characters." }
    }
    func retrySave() { saveCandidate(deliverAfterSave: false) }
    private func saveCandidate(deliverAfterSave: Bool) {
        guard canRetrySave, let candidate = continuation.candidate else { return }
        do {
            let saved = try session.stage(candidate.request, candidate.ticket)
            try continuation.acknowledge(saved)
            text = ""; refresh()
            if deliverAfterSave, !saved.isComplete { requestDelivery(saved, replay: false) }
        } catch { message = "Your question could not be saved. Retry saving the same question." }
    }
    func sendSaved() {
        guard isCurrent, hasStatus, !deliveryRequested, let pending = unfinished, pending.state == .pending else { return }
        requestDelivery(pending.intent, replay: false)
    }
    func recoverSaved() {
        guard isCurrent, hasStatus, canRecover, !deliveryRequested, let pending = unfinished,
              pending.state == .held || pending.state == .running else { return }
        requestDelivery(pending.intent, replay: true)
    }
    private func requestDelivery(_ intent: ProtectedInsightChatIntent, replay: Bool) {
        guard isCurrent else { return }
        do {
            deliveryRequested = try session.deliver(intent, replay)
            refresh(after: pageAfter)
            message = deliveryRequested ? "Checking your saved question…" : "Your question is saved. Try again when a connection is available."
        } catch { message = "This question cannot be retried yet. Refresh its saved status." }
    }
    func deliveryFinished() { deliveryRequested = false; refresh(after: pageAfter) }
    func close() {
        guard !closed else { return }
        closed = true; session.close(); completed = []; unfinished = nil; text = ""
        // The continuation and the queue deliberately outlive this sheet.
    }
}
