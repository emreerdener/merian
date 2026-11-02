import Foundation
import Observation

/// Noneditable local holding status. Discovery and explicit selection perform
/// reads only; neither a missing candidate nor Close authorizes resubmission.
@MainActor @Observable
final class CaptureNativeRecoveryModel {
    typealias Candidate = SharedMediaNativeReceivedCandidate
    enum State: Equatable {
        case closed, checking, unavailable
        case unselected([Candidate])
        case holding(Candidate)
    }

    enum ResultStatus: Equatable { case unavailable, idle, reserving, checking, paused, needsAttention, available }
    private(set) var resultStatus: ResultStatus = .unavailable
    private var availableCandidate: Candidate?
    var resultAvailable: Bool {
        guard isCurrent, case .holding(let candidate) = state else { return false }
        return availableCandidate == candidate
    }
    private let statusAccess: CaptureNativeRecoveryStatusAccess?
    private var statusTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var interval: CaptureNativeRecoveryStatusAccess.Interval?
    private var visibleStart: ContinuousClock.Instant?
    #if DEBUG
    private(set) var frozenVisibleElapsedForTesting: Duration?
    #endif
    private var statusToken = UUID()
    private var visible = true
    var hasStatusAction: Bool { statusAccess != nil }
    var canCheckStatus: Bool {
        guard case .holding = state else { return false }
        return hasStatusAction && visible && isCurrent && statusTask == nil && cleanupTask == nil
    }

    private(set) var state: State = .closed
    private let ownerID: UUID
    private let current: () -> Bool
    var isCurrent: Bool { current() }
    private let discover: () async throws -> [Candidate]
    private var presentation = UUID()
    private var profile: SharedMediaNativeAppProfile?

    /// isCurrent binds the caller's account, container and lifetime generation.
    /// The existing native owner independently checks its retained dispatch grant.
    init(ownerID: UUID, isCurrent: @escaping () -> Bool,
         statusAccess: CaptureNativeRecoveryStatusAccess? = nil,
         discover: @escaping () async throws -> [Candidate]) {
        self.ownerID = ownerID; self.current = isCurrent; self.discover = discover
        self.statusAccess = statusAccess
        resultStatus = statusAccess == nil ? .unavailable : .idle
    }

    func open() async { await read(selected: nil) }

    func select(_ candidate: Candidate) async {
        guard case .unselected(let candidates) = state, candidates.contains(candidate) else { return }
        await read(selected: candidate)
    }

    func refresh() async {
        guard case .holding(let candidate) = state else { return }
        await read(selected: candidate)
    }

    /// Also used by the account/container presentation owner on invalidation.
    /// Ends visible checking and starts retained presentation settlement only;
    /// it does not cancel analysis, delete media or shut down the native owner.
    func close() {
        stopChecking(as: .paused)
        presentation = UUID()
        profile = nil
        availableCandidate = nil
        state = .closed
    }

    /// The retained cleanup also keeps this model alive after sheet dismissal.
    /// Account teardown can await it; every settlement reacquires and validates
    /// the original native authority, so teardown can conservatively deny it.
    func closeAndWait() async { close(); await waitForStatusCleanup() }
    func waitForStatusCleanup() async { await cleanupTask?.value }

    func setVisible(_ value: Bool) {
        visible = value
        if !value { stopChecking(as: .paused) }
    }
    func pauseChecking() { stopChecking(as: .paused) }

    /// One explicit availability request. Discovery/selection/foreground never
    /// starts this action, and a found result is not imported or selected here.
    func checkStatus() {
        guard canCheckStatus, case .holding(let candidate) = state, let statusAccess else { return }
        let token = UUID(); statusToken = token
        resultStatus = .reserving
        availableCandidate = nil
        statusTask = Task { [self] in
            do {
                interval = try await statusAccess.reserve(candidate)
                guard statusToken == token else { return }
                guard visible, isCurrent else { stopChecking(as: .needsAttention); return }
                if let interval {
                    let start = ContinuousClock.now
                    visibleStart = start
                    resultStatus = .checking
                    expiryTask = Task { [self] in
                        do { try await ContinuousClock().sleep(until: start + interval.allowance) }
                        catch { return }
                        guard statusToken == token else { return }
                        stopChecking(as: .needsAttention)
                    }
                } else { resultStatus = .needsAttention }
                let found = try await statusAccess.check(candidate)
                guard statusToken == token else { return }
                guard visible, isCurrent else { stopChecking(as: .needsAttention); return }
                availableCandidate = found ? candidate : nil
                stopChecking(as: found ? .available : .needsAttention)
            } catch {
                guard statusToken == token else { return }
                stopChecking(as: .needsAttention)
            }
            // Authority may disappear without the view delivering an event.
            if statusToken == token { stopChecking(as: .needsAttention) }
        }
    }

    private func stopChecking(as status: ResultStatus) {
        guard let work = statusTask, cleanupTask == nil else { return }
        // Freeze before cancellation/drain/persistence. A late acknowledgement
        // after this boundary owns zero visible time and never starts a clock.
        let elapsed = visibleStart?.duration(to: .now) ?? .zero
        visibleStart = nil
        #if DEBUG
        frozenVisibleElapsedForTesting = elapsed
        #endif
        statusToken = UUID()
        expiryTask?.cancel(); expiryTask = nil
        work.cancel()
        statusTask = nil
        resultStatus = status
        cleanupTask = Task { [self] in
            await work.value
            let acknowledged: Bool
            if let interval { acknowledged = (try? await interval.settle(elapsed)) == true }
            else { acknowledged = false }
            interval = nil
            if !acknowledged { resultStatus = .needsAttention }
            cleanupTask = nil
        }
    }

    private func read(selected: Candidate?) async {
        guard state != .checking, statusTask == nil else { return }
        let opening = presentation
        await waitForStatusCleanup()
        guard opening == presentation else { return }
        guard isCurrent, !Task.isCancelled else { state = .unavailable; return }
        let token = presentation
        if selected == nil || selected != availableCandidate {
            availableCandidate = nil
            resultStatus = statusAccess == nil ? .unavailable : .idle
        }
        state = .checking
        do {
            let candidates = try await discover()
            guard presentation == token else { return }
            guard isCurrent, !Task.isCancelled,
                  candidates.count <= PhotoPreparationPolicy.maximumPackages,
                  Set(candidates.map(\.packageID)).count == candidates.count,
                  candidates.allSatisfy({ $0.profile.ownerID == ownerID }) else {
                state = .unavailable; return
            }
            let expectedProfile = profile ?? candidates.first?.profile
            guard candidates.allSatisfy({ $0.profile == expectedProfile }) else {
                state = .unavailable; return
            }
            profile = expectedProfile
            if let selected {
                guard candidates.contains(selected) else { state = .unavailable; return }
                state = .holding(selected)
            } else {
                // Even a single candidate requires explicit exact selection.
                // Empty does not prove there is no other durable work.
                state = .unselected(candidates)
            }
        } catch {
            guard presentation == token else { return }
            state = .unavailable
        }
    }
}
