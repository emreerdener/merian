import Foundation
import Observation
import SwiftData

/// Retains one displayed review across rerenders and uncertain saves. It owns
/// presentation only; the durable queue remains the sole delivery owner.
@MainActor @Observable
final class SelectedAnalysisReviewHost {
    struct Key: Equatable {
        let baseline: SelectedAnalysisReviewBaseline
        let generation: UInt64
        let container: ObjectIdentifier
    }
    private(set) var key: Key?
    private(set) var token: UUID?
    private(set) var model: IdentificationHistoryReviewModel?
    private(set) var message: String?
    private var session: SelectedAnalysisReviewSession?
    private var presentationIsCurrent: () -> Bool = { false }
    private var terminal = false

    var scopeIsCurrent: Bool { session.map { presentationIsCurrent() && $0.isScopeCurrent() } ?? false }
    var deliveryGeneration: UInt64 { session?.access.generation() ?? 0 }

    func bind(_ key: Key, access: SelectedAnalysisReviewAccess, container: ModelContainer,
              isCurrent: @escaping () -> Bool) {
        guard self.key != key else { return }
        close()
        self.key = key
        presentationIsCurrent = isCurrent
        guard ObjectIdentifier(container) == key.container, isCurrent() else { terminal = true; return }
        do {
            let opened = try access.open(key.baseline, container)
            guard isCurrent(), opened.isScopeCurrent(), opened.matchesDisplayedTicket() else {
                opened.close(); terminal = true; return
            }
            let token = UUID()
            self.token = token; session = opened
            model = opened.reviewModel(presentationIsCurrent: { [weak self] in
                guard let self else { return false }
                return self.token == token && self.key == key && self.presentationIsCurrent()
            })
            model?.open()
            message = model?.message
        } catch {
            terminal = true
            message = "This identification is unavailable for review. Open the scan again to refresh it."
        }
    }

    /// Freeze the already-displayed ticket at the actual tap. The returned
    /// handle can cross child dismissal, but cannot reopen or retarget a session.
    func preparePublication(token: UUID, container: ModelContainer,
                            continuation: PublicationConsentContinuation, isCurrent: @escaping () -> Bool,
                            present: @escaping (IdentificationPublicationModel) -> Void) -> CommunityConsentTicket? {
        guard isCurrent(), accepts(token), permitsPublication(), let key, key.container == ObjectIdentifier(container),
              let session, session.matchesDisplayedTicket(), let access = session.publication,
              let photo = session.photo else { return nil }
        continuation.bind(owner: session.ticket.ownerID, observation: session.ticket.observationID, container: container)
        guard continuation.matches(session.ticket) else { return nil }
        return CommunityConsentTicket { [weak self] in
            guard let self, isCurrent(), self.accepts(token), self.permitsPublication(), self.key == key,
                  session.matchesDisplayedTicket(), continuation.matches(session.ticket) else { return }
            let model = IdentificationPublicationModel(ticket: session.ticket, access: access, continuation: continuation,
                isCurrent: { [weak self] in
                    guard let self else { return false }
                    return isCurrent() && self.token == token && self.key == key && self.scopeIsCurrent
                        && session.matchesDisplayedTicket()
                }, photo: photo)
            present(model)
        }
    }

    var hasPublicationAccess: Bool {
        session?.publication != nil && session?.photo != nil && scopeIsCurrent && !terminal && model?.hasUnresolvedRequest != true
    }
    private func permitsPublication() -> Bool {
        guard model?.hasUnresolvedRequest != true, let session else { return false }
        do { return try session.access.pending() == nil } catch { return false }
    }

    func prepareNameConfirmation(token: UUID, isCurrent: @escaping () -> Bool) -> SelectedAnalysisNameConfirmation? {
        guard isCurrent(), accepts(token), let key, let session, let model,
              session.matchesDisplayedTicket(), model.canSubmit, model.ticket.canConfirmName else { return nil }
        // This also fails closed on a newly pending review or an unreadable store.
        guard (try? session.access.pending() == nil) == true else { return nil }
        return .init(review: model, isCurrent: { [weak self] in
            guard let self else { return false }
            return isCurrent() && self.token == token && self.key == key && self.model === model
                && self.scopeIsCurrent && session.matchesDisplayedTicket()
        }, submit: { [weak self] name in self?.submit(.confirmName(name), token: token) })
    }

    func prepareCandidateConfirmation(token: UUID, isCurrent: @escaping () -> Bool) -> AnalysisCandidateReviewModel? {
        guard isCurrent(), accepts(token), let key, let session, let model,
              session.matchesDisplayedTicket(), model.canSubmit, !model.ticket.candidateChoices.isEmpty,
              (try? session.access.pending() == nil) == true else { return nil }
        return .init(review: model, isCurrent: { [weak self] in
            guard let self else { return false }
            return isCurrent() && self.token == token && self.key == key && self.model === model
                && self.scopeIsCurrent && session.matchesDisplayedTicket()
        }, loadPhoto: session.photo, confirm: { [weak self] reference in self?.submit(.confirmCandidate(reference), token: token) })
    }

    func submit(_ decision: ObservationAnalysisReviewRequest.Decision, token: UUID) {
        guard accepts(token) else { return }
        model?.submit(decision)
        message = model?.message
    }
    func retrySave(token: UUID) {
        guard accepts(token) else { return }
        model?.retrySave()
        message = model?.message
    }
    func refresh(onApplied: (Key) -> Void) {
        guard !terminal, let token, accepts(token), let model, let key else { return }
        model.refresh()
        message = model.message
        guard let text = model.terminalMessage else { return }
        message = text; terminal = true
        // Consume before invoking the parent bridge: a synchronous presentation
        // change or duplicate delivery epoch must never apply this receipt twice.
        if case .complete(.applied) = model.status?.phase, scopeIsCurrent { onApplied(key) }
        retireScope()
    }
    private func accepts(_ token: UUID) -> Bool {
        guard !terminal, self.token == token, scopeIsCurrent else {
            if self.token == token { terminal = true; retireScope() }
            return false
        }
        return true
    }
    func invalidateScope() {
        terminal = true
        retireScope()
        message = nil
    }
    private func retireScope() {
        model?.close(); model = nil
        session?.close(); session = nil
        token = nil
    }
    func close() {
        retireScope()
        key = nil; message = nil; terminal = false
        presentationIsCurrent = { false }
    }
}
