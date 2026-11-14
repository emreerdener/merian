import Foundation
import Observation

/// Parent-retained current-video candidate. Dismissal never grants a replacement or cancels queue work.
@MainActor @Observable
final class CaptureVideoReanalysisHost {
    struct Presentation: Equatable { fileprivate let id: UUID }
    private(set) var isPresented = false
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var selected: ObservationReanalysisLocalVideoInput.Choice?
    private var opened: CaptureVideoReanalysisAccess.Opened?
    private var presentation = UUID()
    private var work: Task<Void, Never>?
    private var invalidated = false
    private var invalidationHandler: (() -> Void)?

    init(opened: CaptureVideoReanalysisAccess.Opened) { self.opened = opened }
    var choices: [ObservationReanalysisLocalVideoInput.Choice] { opened?.choices ?? [] }
    var analysisID: UUID? { opened?.session.plan?.analysisID }
    var isFrozen: Bool { opened?.session.plan != nil }
    var isCurrent: Bool { !invalidated && opened?.isCurrent() == true }
    var presentedScope: Presentation? { isPresented ? Presentation(id: presentation) : nil }
    func matches(_ scope: Presentation?) -> Bool { scope?.id == presentation && isPresented && isCurrent }
    func close(_ scope: Presentation?) { if scope?.id == presentation { close() } }
    func validatePresentation() { _ = validate() }

    @discardableResult func present() -> Bool {
        guard validate(), work == nil else { return false }
        if isPresented { return true }
        presentation = UUID(); isPresented = true; message = nil
        return true
    }

    func select(_ choice: ObservationReanalysisLocalVideoInput.Choice, scope: Presentation?) {
        guard matches(scope), work == nil, !isFrozen, choices.contains(choice), validate() else { return }
        selected = choice; message = nil
    }

    func submit(descriptions: [String], scope: Presentation?) {
        guard matches(scope), work == nil, validate(), let opened, let selected else { return }
        do {
            try opened.session.freeze(selected, descriptions: descriptions, generation: opened.session.generation)
        } catch {
            message = "This video cannot be submitted. Any existing request has been kept."
            return
        }
        let expected = presentation
        isBusy = true; message = nil
        work = Task { [weak self] in
            guard let self else { return }
            defer { work = nil; isBusy = false }
            do {
                let result = try await opened.submit { [weak self] in
                    self?.presentation == expected && self?.isPresented == true && self?.isCurrent == true
                }
                guard presentation == expected, isPresented, !Task.isCancelled, validate() else { return }
                switch result {
                case .started, .coalesced:
                    message = "Your saved video request is being checked. Completed results appear in identification history."
                case .unavailable:
                    message = "This request cannot continue right now. Check the same saved request again later."
                }
            } catch {
                guard presentation == expected, isPresented, !Task.isCancelled, validate() else { return }
                message = "The outcome is not confirmed. Your original video request has been kept."
            }
        }
    }

    func retry(scope: Presentation?) {
        guard let descriptions = opened?.session.plan?.descriptions else { return }
        submit(descriptions: descriptions, scope: scope)
    }

    func close() {
        presentation = UUID(); isPresented = false; message = nil
        work?.cancel()
        // The same input/candidate and active waiter survive until actual exit.
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true; close(); selected = nil
        invalidationHandler?()
    }

    var isRuntimeQuiescent: Bool { work == nil && opened?.session.isRuntimeQuiescent != false }

    /// Cleanup remains token-bound even after account invalidation. False keeps the host retained.
    func invalidateAndAwait() async -> Bool {
        invalidate()
        let active = work
        await active?.value
        guard let opened else { return true }
        guard await opened.session.shutdown() else { return false }
        self.opened = nil
        return true
    }

    func onInvalidation(_ action: @escaping () -> Void) { invalidationHandler = action }
    @discardableResult private func validate() -> Bool {
        guard isCurrent else { invalidate(); return false }
        return true
    }
}
