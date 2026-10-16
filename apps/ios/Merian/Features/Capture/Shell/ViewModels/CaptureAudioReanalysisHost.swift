import Foundation
import Observation
import SwiftData

/// Parent-retained candidate. Closing its presentation never releases uncertain request occupancy.
@MainActor @Observable
final class CaptureAudioReanalysisHost {
    private(set) var isPresented = false
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var isPreparingInput = false
    private(set) var preparedInput: Data?
    private var inputWork: Task<Void, Never>?
    private var picker: UUID?
    struct Presentation: Equatable { fileprivate let id: UUID }
    struct InputSelection: Equatable { fileprivate let presentation: UUID; fileprivate let id: UUID }

    var presentedScope: Presentation? { isPresented ? Presentation(id: presentation) : nil }
    func matches(_ scope: Presentation?) -> Bool {
        scope?.id == presentation && isPresented && isCurrent
    }
    func close(_ scope: Presentation?) { if scope?.id == presentation { close() } }
    func validatePresentation() { _ = validate() }

    func beginInputSelection(_ scope: Presentation?) -> InputSelection? {
        guard matches(scope), !isFrozen, work == nil, inputWork == nil, picker == nil else { return nil }
        let id = UUID(); picker = id
        return InputSelection(presentation: presentation, id: id)
    }

    func cancelInputSelection(_ selection: InputSelection) {
        guard selection.presentation == presentation, picker == selection.id else { return }
        picker = nil
    }

    func finishInputSelection(_ selection: InputSelection, result: Result<URL, Error>, using preparer: CaptureAudioInputPreparer) {
        guard selection.presentation == presentation, picker == selection.id else { return }
        picker = nil
        guard isPresented, validate() else { return }
        switch result {
        case let .success(url): prepareInput(from: url, using: preparer)
        case let .failure(error):
            if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != CocoaError.userCancelled.rawValue {
                message = "This audio could not be opened. Choose the file again."
            }
        }
    }
    enum Route: Hashable { case legacy, source }
    @MainActor private enum Opened {
        case legacy(CaptureAudioReanalysisAccess.Opened)
        case source(CaptureAudioSourceReanalysisAccess.Opened)

        var session: CaptureAudioReanalysisSession {
            switch self {
            case let .legacy(value): return value.session
            case let .source(value): return value.session
            }
        }
        func isCurrent() -> Bool {
            switch self {
            case let .legacy(value): return value.isCurrent()
            case let .source(value): return value.isCurrent()
            }
        }
        func submit(_ current: @escaping @MainActor @Sendable () -> Bool) async throws -> CaptureAudioReanalysisSession.SourceAdmission {
            switch self {
            case let .legacy(value): return .init(try await value.submit(current))
            case let .source(value): return try await value.submit(current)
            }
        }
    }
    let route: Route
    private var opened: Opened?
    private var presentation = UUID()
    private var work: Task<Void, Never>?
    private var invalidationHandler: (() -> Void)?

    init(opened: CaptureAudioReanalysisAccess.Opened) { self.opened = .legacy(opened); route = .legacy }
    init(source: CaptureAudioSourceReanalysisAccess.Opened) { opened = .source(source); route = .source }

    var analysisID: UUID? { opened?.session.plan?.analysisID }
    var isFrozen: Bool { opened?.session.plan != nil }
    var isCurrent: Bool { opened?.isCurrent() == true }

    /// Reopening uses the original source and candidate, never a fresh access.open call.
    @discardableResult func present() -> Bool {
        guard validate(), work == nil, inputWork == nil else { return false }
        if isPresented { return true }
        presentation = UUID(); isPresented = true; message = nil
        return true
    }

    /// Preparation holds no account lease and cannot create a durable request.
    func prepareInput(from url: URL, using preparer: CaptureAudioInputPreparer) {
        guard isPresented, work == nil, inputWork == nil, picker == nil, !isFrozen, validate() else { return }
        let expected = presentation
        preparedInput = nil; message = nil; isPreparingInput = true
        inputWork = Task { [weak self] in
            guard let self else { return }
            defer { inputWork = nil; isPreparingInput = false }
            do {
                let bytes = try await preparer.prepare(url)
                guard !Task.isCancelled, presentation == expected, isPresented, validate() else { return }
                preparedInput = bytes
            } catch {
                guard !Task.isCancelled, presentation == expected, isPresented, validate() else { return }
                message = "This audio could not be prepared. Choose the file again."
            }
        }
    }

    func submitPrepared(descriptionsBefore: [String] = [], descriptionsAfter: [String] = []) {
        guard let preparedInput else { return }
        submit(descriptionsBefore.map(CaptureAudioReanalysisPlan.Choice.description) + [.audio(preparedInput)] +
            descriptionsAfter.map(CaptureAudioReanalysisPlan.Choice.description))
    }

    func submit(_ choices: [CaptureAudioReanalysisPlan.Choice]) {
        guard isPresented, work == nil, inputWork == nil, picker == nil, validate(), let opened else { return }
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
        presentation = UUID(); isPresented = false; message = nil; picker = nil
        work?.cancel()
        inputWork?.cancel(); preparedInput = nil
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

    func open(target: HistoricalReanalysisTarget, container: ModelContainer, route: CaptureAudioReanalysisHost.Route = .legacy,
              make: () throws -> CaptureAudioReanalysisHost) throws -> CaptureAudioReanalysisHost {
        guard !isInvalidated else { throw ObservationHistoryError.accountChanged }
        // Do not discard a stale entry and silently authorize a replacement in a newer account scope.
        guard hosts.values.allSatisfy(\.isCurrent) else {
            invalidate(); throw ObservationHistoryError.accountChanged
        }
        let key = Key(owner: target.ownerID, observation: target.observationID,
            source: target.analysisID, container: ObjectIdentifier(container))
        if let host = hosts[key] {
            guard host.route == route else { throw ObservationHistoryError.unavailable }
            return host
        }
        guard hosts.count < 4 else { throw ObservationHistoryError.unavailable }
        let host = try make()
        guard !isInvalidated, host.isCurrent, host.route == route else { host.invalidate(); throw ObservationHistoryError.accountChanged }
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
