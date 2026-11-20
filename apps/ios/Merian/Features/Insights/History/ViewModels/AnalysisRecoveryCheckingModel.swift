import Foundation
import Observation

/// Visible checking is separate from the retained exact-operation owner.
@MainActor @Observable
final class AnalysisRecoveryCheckingModel {
    enum State: Equatable { case idle, preparing, checking, paused, needsAttention, recovered, unavailable }
    struct Interval {
        let allowance: Duration
        let settle: (Duration) throws -> Void
    }
    struct Access {
        let isCurrent: () -> Bool
        let reserve: () async throws -> Interval?
        let check: () async throws -> Bool
    }
    private(set) var state: State = .idle
    private(set) var isRunning = false
    private(set) var isClosed = false
    private var visible = true
    private var pendingCompletion: Bool?
    private let didFinish: () -> Void
    private let access: Access
    private let now: () -> ContinuousClock.Instant
    private let sleep: (ContinuousClock.Instant) async throws -> Void
    private var work: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var interval: Interval?
    private var visibleStart: ContinuousClock.Instant?
    var canCheck: Bool { !isClosed && visible && !isRunning && access.isCurrent() }

    init(access: Access, didFinish: @escaping () -> Void = {}, now: @escaping () -> ContinuousClock.Instant = { .now },
         sleep: @escaping (ContinuousClock.Instant) async throws -> Void = { try await ContinuousClock().sleep(until: $0) }) {
        self.access = access; self.didFinish = didFinish; self.now = now; self.sleep = sleep
    }

    var message: String? {
        switch state {
        case .idle: nil
        case .preparing: "Opening your saved request."
        case .checking: "We lost confirmation of your result. We’re checking whether it finished."
        case .paused: "Checking is paused. Your original request has been kept."
        case .needsAttention: "We haven’t been able to recover your result yet."
        case .recovered: "Your original result is available in identification history."
        case .unavailable: "The original result cannot be checked right now."
        }
    }

    func check() {
        guard canCheck else { return }
        isRunning = true; state = .preparing
        // Accept once at the tap. Account/operation ownership governs this
        // retained task even if the sheet closes before it first executes.
        work = Task { [self] in
            guard access.isCurrent() else { finish(found: false); return }
            do { interval = try await access.reserve() } catch {
                finish(found: false)
                if !isClosed, visible, access.isCurrent() { state = .unavailable }
                return
            }
            guard access.isCurrent() else { finish(found: false); return }
            if visible, !isClosed {
                if let interval {
                    let start = now()
                    visibleStart = start; state = .checking
                    expiry = Task { [self] in
                        do { try await sleep(start + interval.allowance) } catch { return }
                        guard !Task.isCancelled, !isClosed, visibleStart != nil else { return }
                        pause(as: .needsAttention)
                    }
                } else { state = .needsAttention }
            } else {
                // A late reservation acknowledgement after leaving the screen
                // owns zero visible time. It still cannot cancel the check.
                pause(as: .paused)
            }
            let found: Bool
            do { found = try await access.check() } catch { finish(found: false); return }
            finish(found: found)
        }
    }

    func setVisible(_ value: Bool) {
        visible = value
        if !value, isRunning { pause(as: .paused) }
        guard access.isCurrent() else { close(); return }
        if value, !isClosed, let found = pendingCompletion {
            pendingCompletion = nil
            state = found ? .recovered : .needsAttention
            didFinish()
        }
    }
    func close() {
        guard !isClosed else { return }
        pause(as: .paused); isClosed = true; visible = false
        state = .unavailable; pendingCompletion = nil
    }
    private func finish(found: Bool) {
        // Completion/removal may already have won the sidecar transaction.
        // That is never permission to recreate it or reject the known result.
        pause(as: .needsAttention)
        work = nil; isRunning = false
        guard !isClosed, access.isCurrent() else { close(); return }
        if visible { state = found ? .recovered : .needsAttention; didFinish() } else { pendingCompletion = found }
    }
    private func pause(as next: State) {
        let live = interval
        let elapsed = visibleStart.map { $0.duration(to: now()) } ?? .zero
        interval = nil; visibleStart = nil
        // Settle before cancelling the timer, including when the timer itself
        // calls this method. Cancellation must not poison the persistence CAS.
        if let live { try? live.settle(elapsed) }
        expiry?.cancel(); expiry = nil
        if !isClosed { state = next }
    }
}
