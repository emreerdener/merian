import Foundation
import Observation

/// Parent-retained candidate. Closing its presentation never releases uncertain request occupancy.
@MainActor @Observable
final class CaptureAudioReanalysisHost {
    private(set) var isPresented = false
    private(set) var isBusy = false
    private(set) var message: String?
    private var opened: CaptureAudioReanalysisAccess.Opened?
    private var presentation = UUID()
    private var work: Task<Void, Never>?

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
        close(); opened = nil
    }

    @discardableResult private func validate() -> Bool {
        guard isCurrent else { invalidate(); return false }
        return true
    }
}
