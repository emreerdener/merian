import Foundation
import Observation
import UIKit

/// One immutable displayed target. No idle lease or polling owns this UI.
@MainActor @Observable
final class IdentificationPublicationModel {
    enum Phase { case idle, checking, vacant, preparing, choosing, occupied, uncertain, submitted, closed }
    let ticket: ObservationAnalysisReviewTicket
    private(set) var phase: Phase = .idle
    private(set) var candidates: [ObservationPublicationConsentSnapshot.Photo] = []
    private(set) var selected: [UUID] = []
    private(set) var recovery: ObservationPublicationTargetRecovery?
    private(set) var status: ObservationPublicationOperationStatus?
    private(set) var message: String?
    private(set) var photo: UIImage?
    private(set) var photoID: UUID?
    private var prepared: ObservationPublicationConsentService.Prepared?
    private var saved: (ObservationAnalysisReviewTicket, UUID)?
    private var work: Task<Void, Never>?
    private var photoGeneration = 0
    private let access: IdentificationHistoryPublicationAccess
    private let continuation: PublicationConsentContinuation
    private let isCurrent: () -> Bool
    private let load: (UUID, UUID) async throws -> UIImage
    var deliveryGeneration: UInt64 { access.generation() }
    var isScopeCurrent: Bool { phase != .closed && isCurrent() && continuation.matches(ticket) }
    var isBusy: Bool { phase == .checking || phase == .preparing }
    var canSubmit: Bool { phase == .choosing && !selected.isEmpty && !continuation.isOccupied }
    var canRetrySave: Bool { phase != .closed && continuation.matches(ticket) && continuation.held != nil }

    init(ticket: ObservationAnalysisReviewTicket, access: IdentificationHistoryPublicationAccess,
         continuation: PublicationConsentContinuation, isCurrent: @escaping () -> Bool,
         photo: @escaping (UUID, UUID) async throws -> UIImage) {
        self.ticket = ticket; self.access = access; self.continuation = continuation
        self.isCurrent = isCurrent; load = photo
        if continuation.held != nil { phase = .uncertain; message = "An earlier sharing choice needs to be saved. Retry that same choice." } else if continuation.isOccupied { phase = .occupied }
    }
    func startRecovery() { start { await $0.recover() } }
    func startPreparation() { start { await $0.prepare() } }
    private func start(_ operation: @escaping (IdentificationPublicationModel) async -> Void) {
        guard work == nil, current() else { return }
        work = Task { [weak self] in
            guard let self else { return }
            await operation(self)
            self.work = nil
        }
    }
    func recover() async {
        defer { settleCancellation() }
        guard current(), !isBusy else { return }
        let mayPrepare = phase == .idle && !continuation.isOccupied
        phase = .checking
        do {
            let result = try await access.recoverTarget(ticket)
            guard current() else { return }
            recovery = result
            if result.local != nil || result.remote != .absent { phase = .occupied } else { phase = mayPrepare && !continuation.isOccupied ? .vacant : .uncertain }
            message = phase == .uncertain ? "No new request will be created here. Retry the original saved choice or reopen a fresh preview." : nil
        } catch {
            guard current() else { return }
            phase = .uncertain; message = "Sharing status could not be verified. No new request has been created."
        }
    }
    func prepare() async {
        defer { settleCancellation() }
        guard current(), phase == .vacant, !continuation.isOccupied else { return }
        phase = .preparing
        do {
            let result = try await access.prepare(ticket)
            guard current() else { return }
            guard !continuation.isOccupied else { phase = .occupied; return }
            prepared = result; candidates = result.snapshot.media; selected = []; phase = .choosing
        } catch {
            guard current() else { return }
            phase = .uncertain; message = "This identification cannot be shared from this preview. Refresh it before making a new choice."
        }
    }
    func toggle(_ media: UUID) {
        guard current(), phase == .choosing, !continuation.isOccupied, candidates.contains(where: { $0.mediaID == media }) else { return }
        if selected.contains(media) { selected.removeAll { $0 == media } } else if selected.count < 6 { selected.append(media) }
    }
    /// Final tap creates and retains exactly one acceptance before synchronous persistence.
    func submit() {
        guard current(), canSubmit, let prepared else { return }
        do {
            let acceptance = try prepared.accepting(mediaIDs: selected)
            try continuation.retain(acceptance, ticket: ticket)
            persistHeld()
        } catch {
            phase = .uncertain; message = "This sharing choice could not be saved. No replacement request will be created."
        }
    }
    func retrySave() { guard current(), canRetrySave else { return }; persistHeld() }
    private func persistHeld() {
        guard let held = continuation.held else { return }
        phase = .uncertain
        do {
            try access.stage(held.acceptance)
            // Durable consent is now authoritative, even if this UI lost its scope.
            continuation.acknowledge(held.acceptance.request.operationID)
            guard current() else { return }
            saved = (held.ticket, held.acceptance.request.operationID)
            prepared = nil; candidates = []; selected = []; photo = nil; photoID = nil
            phase = .submitted; message = "Sharing request saved. Your photos will be checked before they can be shared."
            refreshStatus()
        } catch {
            guard current() else { return }
            message = "Saving was not acknowledged. Retry saving the same photos and request."
        }
    }
    func refreshStatus() {
        guard current(), let saved else { return }
        do { status = try access.status(saved.0, saved.1) } catch { message = "The saved request's status is unavailable. Your sharing choice has not been replaced." }
    }
    func previewPhoto(_ media: UUID) async {
        guard current(), phase == .choosing, candidates.contains(where: { $0.mediaID == media }) else { return }
        photoGeneration += 1; let expected = photoGeneration
        photo = nil; photoID = media
        do {
            let image = try await load(ticket.analysisID, media)
            guard current(), phase == .choosing, photoGeneration == expected else { return }
            photo = image
        } catch {
            guard current(), photoGeneration == expected else { return }
            message = "This saved photo is unavailable right now."
        }
    }
    private func current() -> Bool {
        guard phase != .closed, isCurrent(), continuation.matches(ticket) else { close(); return false }
        return !Task.isCancelled
    }
    private func settleCancellation() {
        guard Task.isCancelled, isBusy else { return }
        guard isCurrent(), continuation.matches(ticket) else { close(); return }
        phase = .uncertain
        message = "This check was interrupted. No new request has been created."
    }
    func close() {
        phase = .closed; work?.cancel(); work = nil; photoGeneration += 1
        prepared = nil; candidates = []; selected = []; photo = nil; photoID = nil; recovery = nil; status = nil; saved = nil; message = nil
        // The parent continuation deliberately survives History back/dismissal.
    }
}
