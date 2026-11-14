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
        case savedResults(SharedMediaNativeInitialPage.Kind)
    }

    typealias OriginalRead = @MainActor (Candidate, Int, @escaping NativeReceivedStatusTransport.Validator) async throws -> SharedMediaNativeOriginalPreview
    private let originalRead: OriginalRead?
    private(set) var originalPreview: SharedMediaNativeOriginalPreview?
    private(set) var originalUnavailable = false
    private var originalTask: Task<Void, Never>?
    private var originalCleanup: Task<Void, Never>?
    private var originalGeneration = UUID()
    var hasOriginalAction: Bool { originalRead != nil && !retainedInitial }
    var canViewOriginal: Bool {
        guard case .holding = state else { return false }
        return hasOriginalAction && canReadSavedInitial && originalTask == nil && originalCleanup == nil
    }

    func viewOriginal(index: Int = 0) async {
        guard canViewOriginal, case .holding(let candidate) = state, let originalRead else { return }
        originalPreview = nil; originalUnavailable = false
        let generation = UUID(); originalGeneration = generation
        let token = presentation
        let task = Task { [self] in
            let check: NativeReceivedStatusTransport.Validator = { [self] in
                try Task.checkCancellation()
                guard originalGeneration == generation, presentation == token, visible, isCurrent,
                      state == .holding(candidate), !retainedInitial else { throw SharedMediaStorageFailure.stale }
            }
            do {
                try check()
                let preview = try await originalRead(candidate, index, check)
                try check(); try await preview.validate(); try check()
                guard preview.index == index, (1...2).contains(preview.count),
                      (0..<preview.count).contains(index) else { throw SharedMediaStorageFailure.stale }
                originalPreview = preview
            } catch {
                if originalGeneration == generation { originalPreview = nil; originalUnavailable = true }
            }
        }
        originalTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if originalGeneration == generation { originalTask = nil }
    }

    func checkOriginalScope() async {
        guard let preview = originalPreview, originalTask == nil, originalCleanup == nil else { return }
        let generation = originalGeneration, token = presentation
        let task = Task { [self] in
            do {
                guard visible, isCurrent else { throw SharedMediaStorageFailure.stale }
                try await preview.validate(); try Task.checkCancellation()
                guard visible, isCurrent, presentation == token else { throw SharedMediaStorageFailure.stale }
            } catch {
                if originalGeneration == generation { originalPreview = nil; originalUnavailable = true }
            }
        }
        originalTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if originalGeneration == generation { originalTask = nil }
    }

    func closeOriginal() {
        originalPreview = nil; originalUnavailable = false; originalGeneration = UUID()
        guard let task = originalTask else { return }
        task.cancel(); originalTask = nil
        let previous = originalCleanup
        originalCleanup = Task { [self] in
            await previous?.value; await task.value
            originalCleanup = nil; releaseClosedLifetime()
        }
    }

    typealias InitialPageRead = @MainActor (SharedMediaNativeInitialPage.Kind, SharedMediaNativeInitialPage.Cursor?) async throws -> SharedMediaNativeInitialPage
    private let initialPageRead: InitialPageRead?
    private(set) var savedInitialPage: SharedMediaNativeInitialPage?
    var hasSavedDiscovery: Bool { initialPageRead != nil }
    var canReadSavedInitial: Bool {
        visible && isCurrent && discoveryTask == nil && statusTask == nil && historyTask == nil && cleanupTask == nil
    }

    enum HistoryStatus: Equatable { case idle, saving, held, saved(NativeHistoryAssociation) }
    typealias InitialRead = @MainActor (Candidate) async throws -> SharedMediaNativeInitialContinuation?
    typealias InitialCompletion = @MainActor (Candidate, @escaping NativeReceivedStatusTransport.Validator) async throws -> NativeHistoryAssociation?
    typealias InitialOpen = @MainActor (NativeHistoryAssociation) throws -> Void
    private let initialOpen: InitialOpen?
    var canOpenSavedResult: Bool {
        guard case .holding = state, case .saved = historyStatus else { return false }
        return initialOpen != nil && canReadSavedInitial
    }

    /// Navigation is a separate user action and never changes analysis selection.
    @discardableResult func openSavedResult() -> Bool {
        guard canOpenSavedResult, case .saved(let association) = historyStatus, let initialOpen else { return false }
        do {
            try association.validate()
            guard association.ownerID == ownerID else { throw SharedMediaStorageFailure.stale }
            try initialOpen(association)
            close()
            return true
        } catch { historyStatus = .held; return false }
    }

    private let initialRead: InitialRead?
    private let initialCompletion: InitialCompletion?
    private var historyTask: Task<Void, Never>?
    private var historyGeneration: UUID?
    private var retainedInitial = false
    private(set) var historyStatus: HistoryStatus = .idle
    var hasHistoryAction: Bool { initialRead != nil && initialCompletion != nil }
    var canAddToHistory: Bool {
        guard case .holding = state, historyStatus != .saving else { return false }
        if case .saved = historyStatus { return false }
        return hasHistoryAction && (recordObserved || retainedInitial) && visible && isCurrent
            && historyTask == nil && statusTask == nil && discoveryTask == nil && cleanupTask == nil
    }

    enum ObservationStatus: Equatable { case unavailable, idle, reserving, checking, paused, needsAttention, observed }
    private(set) var observationStatus: ObservationStatus = .unavailable
    private var observedCandidate: Candidate?
    var recordObserved: Bool {
        guard isCurrent, case .holding(let candidate) = state else { return false }
        return observedCandidate == candidate
    }
    private let statusAccess: CaptureNativeRecoveryStatusAccess?
    private var statusTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var discoveryGeneration: UUID?
    private let lifetime: (() -> SharedMediaNativeOriginalDrain?)?
    private weak var attachedLifetime: SharedMediaNativeOriginalDrain?
    private var lifetimeRegistration: SharedMediaNativeOriginalDrain.RecoveryRegistration?
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
        return hasStatusAction && visible && isCurrent && statusTask == nil && historyTask == nil && cleanupTask == nil && !retainedInitial
    }

    private(set) var state: State = .closed
    private let ownerID: UUID
    private let current: () -> Bool
    var isCurrent: Bool {
        guard current() else { return false }
        guard let lifetimeRegistration else { return true }
        return attachedLifetime?.isCurrentRecoveryPresentation(lifetimeRegistration, ownerID: ownerID) == true
    }
    private let discover: () async throws -> [Candidate]
    private var presentation = UUID()
    private var profile: SharedMediaNativeAppProfile?

    /// isCurrent binds the caller's account, container and lifetime generation.
    /// The existing native owner independently checks its retained dispatch grant.
    init(ownerID: UUID, isCurrent: @escaping () -> Bool,
         statusAccess: CaptureNativeRecoveryStatusAccess? = nil,
         lifetime: (() -> SharedMediaNativeOriginalDrain?)? = nil,
         initialRead: InitialRead? = nil, initialCompletion: InitialCompletion? = nil,
         initialPageRead: InitialPageRead? = nil, initialOpen: InitialOpen? = nil,
         originalRead: OriginalRead? = nil,
         discover: @escaping () async throws -> [Candidate]) {
        self.ownerID = ownerID; self.current = isCurrent; self.discover = discover
        self.statusAccess = statusAccess; self.lifetime = lifetime
        self.initialRead = initialRead; self.initialCompletion = initialCompletion; self.initialPageRead = initialPageRead
        self.initialOpen = initialOpen; self.originalRead = originalRead
        observationStatus = statusAccess == nil ? .unavailable : .idle
    }

    func open() async { await read(selected: nil) }

    func select(_ candidate: Candidate) async {
        guard case .unselected(let candidates) = state, candidates.contains(candidate) else { return }
        await read(selected: candidate)
    }

    func refresh() async {
        guard case .holding(let candidate) = state else { return }
        if initialRead != nil { await resumeInitial(candidate) } else { await read(selected: candidate) }
    }

    /// Separate bounded read, including when pending discovery is unavailable.
    /// Pages replace one another; they never accumulate retained prepared data.
    func findSavedInitial(_ kind: SharedMediaNativeInitialPage.Kind, next: Bool = false) async {
        guard canReadSavedInitial, let initialPageRead else { return }
        closeOriginal()
        let cursor: SharedMediaNativeInitialPage.Cursor?
        if next {
            guard case .savedResults(let currentKind) = state, currentKind == kind, let saved = savedInitialPage?.next, saved.kind == kind else { return }
            cursor = saved
        } else { cursor = nil }
        closeOriginal()
        let token = presentation, generation = UUID()
        state = .checking
        let task = Task { [self] in
            do {
                let page = try await initialPageRead(kind, cursor)
                guard presentation == token else { return }
                try Task.checkCancellation()
                guard isCurrent, visible, page.candidates.count <= SharedMediaStoragePolicy.pageSize,
                      Set(page.candidates.map(\.packageID)).count == page.candidates.count,
                      page.candidates.allSatisfy({ $0.profile.ownerID == ownerID }),
                      page.next == nil || (page.next?.kind == kind && page.next?.profile.ownerID == ownerID) else {
                    throw SharedMediaStorageFailure.stale
                }
                let expectedProfile = cursor?.profile ?? page.next?.profile ?? page.candidates.first?.profile
                guard page.candidates.allSatisfy({ $0.profile == expectedProfile }) else { throw SharedMediaStorageFailure.stale }
                try attachLifetime(allowAbsent: kind == .enrollment)
                savedInitialPage = page; state = .savedResults(kind)
                observedCandidate = nil; retainedInitial = false; historyStatus = .idle
            } catch {
                guard presentation == token else { return }
                savedInitialPage = nil; state = .unavailable
            }
        }
        discoveryGeneration = generation; discoveryTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if discoveryGeneration == generation { discoveryTask = nil; discoveryGeneration = nil }
    }

    func selectSavedInitial(_ candidate: Candidate) async {
        guard case .savedResults = state, savedInitialPage?.candidates.contains(candidate) == true else { return }
        await resumeInitial(candidate)
    }

    /// An explicit saved selection may outlive the pending list after application.
    /// The exact frozen candidate is revalidated; this read never resumes work.
    func resumeInitial(_ candidate: Candidate) async {
        guard let initialRead, candidate.profile.ownerID == ownerID, isCurrent, visible,
              state != .checking, discoveryTask == nil, statusTask == nil, historyTask == nil, cleanupTask == nil else { return }
        closeOriginal()
        let token = presentation, generation = UUID()
        state = .checking
        let task = Task { [self] in
            do {
                guard let value = try await initialRead(candidate) else { throw SharedMediaStorageFailure.closed }
                guard token == presentation else { return }
                try Task.checkCancellation()
                guard isCurrent, visible, value.prepared.profile == candidate.profile,
                      value.prepared.package.id == candidate.packageID else { throw SharedMediaStorageFailure.stale }
                try attachLifetime(allowAbsent: value.phase == .enrollmentHeld)
                profile = candidate.profile; retainedInitial = value.phase != .pending
                state = .holding(candidate)
                // Even an acknowledged local lookup is not an automatic route.
                historyStatus = .idle
            } catch {
                guard token == presentation else { return }
                state = .unavailable
            }
        }
        discoveryGeneration = generation; discoveryTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if discoveryGeneration == generation { discoveryTask = nil; discoveryGeneration = nil }
    }

    /// Separate explicit action; availability alone is never completion authority.
    func addToHistory() {
        guard canAddToHistory, case .holding(let candidate) = state, let initialCompletion else { return }
        closeOriginal()
        let token = presentation, generation = UUID()
        historyGeneration = generation; historyStatus = .saving
        historyTask = Task { [self] in
            let check: NativeReceivedStatusTransport.Validator = { [self] in
                try Task.checkCancellation()
                guard presentation == token, historyGeneration == generation, visible, isCurrent else {
                    throw SharedMediaStorageFailure.stale
                }
            }
            defer {
                if historyGeneration == generation { historyTask = nil; historyGeneration = nil }
            }
            do {
                try check()
                let result = try await initialCompletion(candidate, check)
                try check()
                if let result {
                    try result.validate()
                    guard result.ownerID == ownerID else { throw SharedMediaStorageFailure.stale }
                    // Once ordinary native completion succeeds, require its
                    // lifetime normally; a sealed/missing live lifetime is held.
                    try attachLifetime(continuing: true)
                    historyStatus = .saved(result); retainedInitial = true
                } else { historyStatus = .held }
            } catch {
                guard presentation == token, historyGeneration == generation else { return }
                historyStatus = .held
            }
        }
    }

    private func stopHistory() {
        guard let task = historyTask, cleanupTask == nil else { return }
        task.cancel(); historyTask = nil; historyGeneration = nil
        historyStatus = .held
        cleanupTask = Task { [self] in
            await task.value
            cleanupTask = nil; releaseClosedLifetime()
        }
    }

    /// Also used by the account/container presentation owner on invalidation.
    /// Ends visible checking and starts retained presentation settlement only;
    /// it does not cancel analysis, delete media or shut down the native owner.
    func close() {
        closeOriginal()
        stopChecking(as: .paused)
        stopHistory()
        if let discoveryTask, cleanupTask == nil {
            discoveryTask.cancel()
            self.discoveryTask = nil; discoveryGeneration = nil
            cleanupTask = Task { [self] in
                await discoveryTask.value
                cleanupTask = nil
                releaseClosedLifetime()
            }
        }
        presentation = UUID()
        profile = nil; savedInitialPage = nil
        observedCandidate = nil; retainedInitial = false; historyStatus = .idle
        state = .closed
        releaseClosedLifetime()
    }

    private func releaseClosedLifetime() {
        guard state == .closed, cleanupTask == nil, originalCleanup == nil, originalTask == nil, let lifetimeRegistration else { return }
        attachedLifetime?.unregisterRecoveryPresentation(lifetimeRegistration)
        self.lifetimeRegistration = nil; attachedLifetime = nil
    }

    private func attachLifetime(allowAbsent: Bool = false, continuing: Bool = false) throws {
        guard let lifetime else { return }
        guard state == .checking || continuing, isCurrent, !Task.isCancelled else { throw SharedMediaStorageFailure.closed }
        guard let value = lifetime() else {
            guard allowAbsent, lifetimeRegistration == nil, attachedLifetime == nil else { throw SharedMediaStorageFailure.closed }
            return
        }
        if lifetimeRegistration != nil {
            guard attachedLifetime === value else { throw SharedMediaStorageFailure.closed }
            return
        }
        let token = try value.registerRecoveryPresentation(ownerID: ownerID) { [self] in await closeAndWait() }
        attachedLifetime = value; lifetimeRegistration = token
    }

    /// The retained cleanup also keeps this model alive after sheet dismissal.
    /// Account teardown can await it; every settlement reacquires and validates
    /// the original native authority, so teardown can conservatively deny it.
    func closeAndWait() async { close(); await waitForStatusCleanup() }
    func waitForStatusCleanup() async { await cleanupTask?.value; await originalCleanup?.value }

    func setVisible(_ value: Bool) {
        visible = value
        if !value { closeOriginal(); stopChecking(as: .paused); stopHistory() }
    }
    func pauseChecking() { stopChecking(as: .paused) }

    /// One explicit availability request. Discovery/selection/foreground never
    /// starts this action, and a found result is not imported or selected here.
    func checkStatus() {
        guard canCheckStatus, case .holding(let candidate) = state, let statusAccess else { return }
        closeOriginal()
        let token = UUID(); statusToken = token
        observationStatus = .reserving
        observedCandidate = nil
        statusTask = Task { [self] in
            do {
                interval = try await statusAccess.reserve(candidate)
                guard statusToken == token else { return }
                guard visible, isCurrent else { stopChecking(as: .needsAttention); return }
                if let interval {
                    let start = ContinuousClock.now
                    visibleStart = start
                    observationStatus = .checking
                    expiryTask = Task { [self] in
                        do { try await ContinuousClock().sleep(until: start + interval.allowance) } catch { return }
                        guard statusToken == token else { return }
                        stopChecking(as: .needsAttention)
                    }
                } else { observationStatus = .needsAttention }
                let found = try await statusAccess.check(candidate)
                guard statusToken == token else { return }
                guard visible, isCurrent else { stopChecking(as: .needsAttention); return }
                observedCandidate = found ? candidate : nil
                stopChecking(as: found ? .observed : .needsAttention)
            } catch {
                guard statusToken == token else { return }
                stopChecking(as: .needsAttention)
            }
            // Authority may disappear without the view delivering an event.
            if statusToken == token { stopChecking(as: .needsAttention) }
        }
    }

    private func stopChecking(as status: ObservationStatus) {
        guard let work = statusTask, cleanupTask == nil else { return }
        // Freeze before cancellation/drain/persistence. A late acknowledgement
        // after this boundary owns zero visible time and never starts a clock.
        let elapsed = visibleStart?.duration(to: .now) ?? .zero
        visibleStart = nil
        #if DEBUG
        frozenVisibleElapsedForTesting = elapsed
        #endif
        statusToken = UUID()
        let expiry = expiryTask
        expiry?.cancel(); expiryTask = nil
        work.cancel()
        statusTask = nil
        observationStatus = status
        cleanupTask = Task { [self] in
            await expiry?.value
            await work.value
            let acknowledged: Bool
            if let interval { acknowledged = (try? await interval.settle(elapsed)) == true } else { acknowledged = false }
            interval = nil
            if !acknowledged { observationStatus = .needsAttention }
            cleanupTask = nil
            releaseClosedLifetime()
        }
    }

    private func read(selected: Candidate?) async {
        guard state != .checking, discoveryTask == nil, statusTask == nil, historyTask == nil else { return }
        closeOriginal()
        let opening = presentation
        await waitForStatusCleanup()
        guard opening == presentation, state != .checking, discoveryTask == nil,
              statusTask == nil, historyTask == nil, cleanupTask == nil else { return }
        guard isCurrent, !Task.isCancelled else { state = .unavailable; return }
        let token = presentation
        if selected == nil || selected != observedCandidate {
            observedCandidate = nil
            observationStatus = statusAccess == nil ? .unavailable : .idle
        }
        retainedInitial = false; historyStatus = .idle
        state = .checking
        let generation = UUID()
        let task = Task { [self] in await discoverAndApply(selected: selected, token: token) }
        discoveryGeneration = generation; discoveryTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if discoveryGeneration == generation { discoveryTask = nil; discoveryGeneration = nil }
    }

    private func discoverAndApply(selected: Candidate?, token: UUID) async {
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
            try attachLifetime()
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
