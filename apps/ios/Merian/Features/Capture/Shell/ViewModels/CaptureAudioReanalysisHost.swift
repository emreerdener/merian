import Foundation
import Observation
import SwiftData

/// Parent-retained candidate. Closing its presentation never releases uncertain request occupancy.
@MainActor @Observable
final class CaptureAudioReanalysisHost {
    private(set) var isPresented = false
    private(set) var isBusy = false
    private(set) var message: String?
    private var opened: CaptureAudioReanalysisAccess.Opened?
    private var presentation = UUID()
    private var work: Task<Void, Never>?
    private var invalidationHandler: (() -> Void)?

    init(opened: CaptureAudioReanalysisAccess.Opened) { self.opened = opened }

    var analysisID: UUID? { opened?.session.plan?.analysisID }
    var isFrozen: Bool { opened?.session.plan != nil }
    var isCurrent: Bool { opened?.isCurrent() == true }

    /// Reopening uses the original source and candidate, never a fresh access.open call.
    @discardableResult func present() -> Bool {
        guard validate(), work == nil else { return false }
        presentation = UUID(); isPresented = true; message = nil
        return true
    }

    func submit(_ choices: [CaptureAudioReanalysisPlan.Choice]) {
        guard isPresented, work == nil, validate(), let opened else { return }
        do {
            // The final tap fixes identity and input before any asynchronous work is scheduled.
            try opened.session.freeze(choices, generation: opened.session.generation)
        } catch {
            message = "This audio cannot be submitted. Any existing request has been kept."
            return
        }
        let expected = presentation
        isBusy = true; message = nil
        work = Task { [weak self] in
            guard let self else { return }
            defer { work = nil; isBusy = false }
            do {
                let admission = try await opened.submit { [weak self] in
                    self?.presentation == expected && self?.isPresented == true && self?.isCurrent == true
                }
                guard presentation == expected, isPresented, !Task.isCancelled, validate() else { return }
                switch admission {
                case .started, .coalesced:
                    message = "Your saved request is being checked. Completed results appear in identification history."
                case .unavailable:
                    message = "This request cannot continue right now. Try the same request again later."
                }
            } catch {
                guard presentation == expected, isPresented, !Task.isCancelled, validate() else { return }
                message = "The outcome is not confirmed. Your original audio request has been kept."
            }
        }
    }

    func retry() {
        guard let choices = opened?.session.plan?.choices else { return }
        submit(choices)
    }

    func close() {
        presentation = UUID(); isPresented = false; message = nil
        work?.cancel()
        // Keep both candidate and waiter until its actual exit. Never cancel the queue owner.
    }

    func invalidate() {
        guard opened != nil else { return }
        close(); opened = nil
        invalidationHandler?()
    }

    func onInvalidation(_ action: @escaping () -> Void) { invalidationHandler = action }

    @discardableResult private func validate() -> Bool {
        guard isCurrent else { invalidate(); return false }
        return true
    }
}

/// One parent lifetime. Capacity never evicts a candidate or grants replacement authority.
@MainActor
final class CaptureAudioReanalysisHostOwner {
    private struct Key: Hashable {
        let owner: UUID
        let observation: UUID
        let source: UUID
        let container: ObjectIdentifier
    }
    private var hosts: [Key: CaptureAudioReanalysisHost] = [:]
    private var isInvalidated = false

    func open(target: HistoricalReanalysisTarget, container: ModelContainer,
              make: () throws -> CaptureAudioReanalysisHost) throws -> CaptureAudioReanalysisHost {
        guard !isInvalidated else { throw ObservationHistoryError.accountChanged }
        // Do not discard a stale entry and silently authorize a replacement in a newer account scope.
        guard hosts.values.allSatisfy(\.isCurrent) else {
            invalidate(); throw ObservationHistoryError.accountChanged
        }
        let key = Key(owner: target.ownerID, observation: target.observationID,
            source: target.analysisID, container: ObjectIdentifier(container))
        if let host = hosts[key] { return host }
        guard hosts.count < 4 else { throw ObservationHistoryError.unavailable }
        let host = try make()
        guard !isInvalidated, host.isCurrent else { host.invalidate(); throw ObservationHistoryError.accountChanged }
        host.onInvalidation { [weak self] in self?.invalidate() }
        hosts[key] = host
        return host
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        for host in hosts.values { host.invalidate() }
        hosts.removeAll()
        // A closed owner cannot become a fresh-admission capability, even after waiters exit.
    }
}
