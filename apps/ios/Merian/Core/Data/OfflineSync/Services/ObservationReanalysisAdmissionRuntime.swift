import Foundation
import SwiftData

/// Local recovery has an independent wake: the general network scheduler cannot run it offline.
@MainActor
final class ObservationReanalysisAdmissionRuntime {
    typealias Store = ObservationReanalysisAdmissionStore
    typealias Validator = ObservationReanalysisPreparationOwner.Validator
    struct Scope {
        let ownerID: UUID
        let container: ModelContainer
        func matches(_ other: Scope?) -> Bool { other?.ownerID == ownerID && other?.container === container }
    }
    enum Opportunity { case automatic, foreground, networkChanged, consentGranted(UUID), submitted(UUID) }
    struct Dependencies {
        var scope: () -> Scope?
        var consentGranted: Validator
        var networkAllowed: Validator
        var execute: (Store.Candidate, ModelContainer, @escaping Validator, @escaping Validator, @escaping Validator) async throws -> ObservationReanalysisAdmissionExecutor.Outcome
        var didAdmit: () -> Void
        var account = ObservationHistoryCloudClient.live
        var now: () -> Date = Date.init
        var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    }
    private struct Entry { let token: UUID; let task: Task<Void, Never>; var cancelled = false }
    private let preparation: ObservationReanalysisPreparationOwner
    private let dependencies: Dependencies
    private var scope: Scope?
    private var entry: Entry?
    private var timers: [UUID: Task<Void, Never>] = [:]
    private var wakeToken: UUID?
    private var drains = 0
    private var rerun = false
    private var grantRetry = false
    private var grantOwner: UUID?
    private var phase: ObservationReanalysisAdmissionWork.Phase?
    private var backoff = ObservationReanalysisAdmissionBackoff()
    private(set) var scheduledWakeDate: Date?
    var isRunning: Bool { entry != nil }

    init(preparation: ObservationReanalysisPreparationOwner, dependencies: Dependencies) {
        self.preparation = preparation; self.dependencies = dependencies
    }

    func request(_ opportunity: Opportunity = .automatic) {
        guard drains == 0, !Task.isCancelled else { return }
        guard let latest = dependencies.scope() else { cancel(); scope = nil; backoff.reset(); return }
        if !latest.matches(scope) {
            cancel(); scope = latest; backoff.reset(); grantOwner = nil
        }
        switch opportunity {
        case .foreground: backoff.reset()
        case .networkChanged:
            backoff.reset()
            if phase == .admissionPending { cancelPass() }
        case let .consentGranted(owner):
            guard owner == latest.ownerID, dependencies.consentGranted() else { return }
            backoff.clear(.discovery)
            grantOwner = owner; grantRetry = true
        case let .submitted(child):
            backoff.clear(.discovery); backoff.clear(.child(child))
        case .automatic: break
        }
        cancelWake()
        if entry != nil { rerun = true; return }
        let token = UUID()
        let task = Task { @MainActor [self] in
            defer { finish(token) }
            await run(latest, token: token)
        }
        entry = .init(token: token, task: task)
    }

    func cancel() {
        cancelWake(); cancelPass(); rerun = false; grantOwner = nil; grantRetry = false
    }

    func cancelAndAwait() async {
        drains += 1
        defer { drains -= 1 }
        cancel()
        let active = entry?.task, sleeping = Array(timers.values)
        for timer in sleeping { await timer.value }
        await active?.value
        backoff.reset(); scope = nil
    }

    private func cancelPass() { entry?.cancelled = true; entry?.task.cancel() }
    private func cancelWake() {
        if let wakeToken { timers[wakeToken]?.cancel() }
        wakeToken = nil; scheduledWakeDate = nil
    }
    private func current(_ expected: Scope, token: UUID) -> Bool {
        entry?.token == token && entry?.cancelled == false && expected.matches(dependencies.scope()) && drains == 0
    }
    private func finish(_ token: UUID) {
        guard entry?.token == token else { return }
        let cancelled = entry?.cancelled == true
        entry = nil; phase = nil
        guard drains == 0 else { return }
        if rerun { rerun = false; request() } else if !cancelled { schedule() }
    }
    private var canPreflight: Bool { dependencies.consentGranted() && dependencies.networkAllowed() }

    private func run(_ expected: Scope, token: UUID) async {
        guard backoff.due(.discovery, proposed: dependencies.now()).map({ $0 <= dependencies.now() }) == true else { return }
        let lease: AccountBoundWorkLease
        do { lease = try dependencies.account.begin(expected.ownerID) } catch {
            if current(expected, token: token) { backoff.failed(.discovery, now: dependencies.now()) }
            return
        }
        defer { dependencies.account.finish(lease) }
        let valid: Validator = { [self] in
            current(expected, token: token) && dependencies.account.isCurrent(lease) && lease.session.userID == expected.ownerID
        }
        guard valid(), !Task.isCancelled else { return }
        do {
            if grantOwner == expected.ownerID, dependencies.consentGranted() {
                // Only an explicit grant event can consume this flag. Timer wakes cannot rearm holds.
                let holds = try Store.consentHolds(ownerID: expected.ownerID, container: expected.container, isCurrent: valid)
                for saved in holds where !preparation.contains(saved.identity.analysisID) {
                    _ = try Store.rearmConsent(saved, now: dependencies.now(), container: expected.container,
                        isCurrent: valid, consentGranted: dependencies.consentGranted)
                }
                grantRetry = false
                if !holds.contains(where: { preparation.contains($0.identity.analysisID) }) { grantOwner = nil }
            }
            let candidates = try Store.candidates(ownerID: expected.ownerID, canPreflight: canPreflight,
                now: dependencies.now(), container: expected.container, isCurrent: valid)
            backoff.clear(.discovery)
            let due = candidates.filter { candidate in
                !preparation.contains(candidate.snapshot.identity.analysisID) &&
                    backoff.due(.child(candidate.snapshot.identity.analysisID), proposed: candidate.due).map { $0 <= dependencies.now() } == true
            }.prefix(8)
            for candidate in due {
                guard valid(), !Task.isCancelled else { return }
                let key = ObservationReanalysisAdmissionBackoff.Key.child(candidate.snapshot.identity.analysisID)
                phase = candidate.snapshot.work.phase
                do {
                    let outcome = try await dependencies.execute(candidate, expected.container,
                        dependencies.consentGranted, dependencies.networkAllowed, valid)
                    guard valid(), !Task.isCancelled else { return }
                    if outcome == .unclaimed { backoff.failed(key, now: dependencies.now()) } else { backoff.clear(key) }
                    if outcome == .admitted { dependencies.didAdmit() }
                } catch {
                    guard valid(), !Task.isCancelled else { return }
                    backoff.failed(key, now: dependencies.now())
                }
                phase = nil
            }
        } catch {
            guard valid(), !Task.isCancelled else { return }
            backoff.failed(.discovery, now: dependencies.now())
            grantRetry = grantOwner != nil
        }
    }

    private func schedule() {
        guard drains == 0, entry == nil, let expected = scope, expected.matches(dependencies.scope()) else { return }
        let instant = dependencies.now()
        let next: Date?
        do {
            let candidates = try Store.candidates(ownerID: expected.ownerID, canPreflight: canPreflight, now: instant,
                container: expected.container, isCurrent: { expected.matches(self.dependencies.scope()) })
            let candidateDate = candidates.filter { !preparation.contains($0.snapshot.identity.analysisID) }
                .compactMap { backoff.due(.child($0.snapshot.identity.analysisID), proposed: $0.due) }.min()
            next = candidateDate ?? (grantRetry && canPreflight ? instant.addingTimeInterval(5) : nil)
        } catch {
            // Unknown phase cannot justify a network-admission fallback while consent/network is closed.
            guard canPreflight else { return }
            next = backoff.due(.discovery, proposed: instant.addingTimeInterval(5))
        }
        guard let proposed = next, let next = backoff.due(.discovery, proposed: proposed) else { return }
        let delay = max(1, next.timeIntervalSince(instant)), token = UUID()
        scheduledWakeDate = instant.addingTimeInterval(delay); wakeToken = token
        let task = Task { @MainActor [self] in
            defer { timers[token] = nil }
            do { try await dependencies.sleep(delay) } catch { return }
            guard !Task.isCancelled, wakeToken == token, expected.matches(dependencies.scope()), drains == 0 else { return }
            wakeToken = nil; scheduledWakeDate = nil
            request()
        }
        timers[token] = task
    }
}

/// Failed reads before durable claim cannot mutate v4. Three local opportunities then external wake only.
struct ObservationReanalysisAdmissionBackoff {
    enum Key: Hashable { case discovery, child(UUID) }
    private struct Failure { let count: Int; let next: Date? }
    private var failures: [Key: Failure] = [:]
    mutating func reset() { failures.removeAll() }
    mutating func clear(_ key: Key) { failures[key] = nil }
    mutating func failed(_ key: Key, now: Date) {
        let count = (failures[key]?.count ?? 0) + 1
        failures[key] = .init(count: count, next: count < 3 ? now.addingTimeInterval(Double(count * 5)) : nil)
    }
    func due(_ key: Key, proposed: Date) -> Date? {
        guard let failure = failures[key] else { return proposed }
        return failure.next.map { max($0, proposed) }
    }
}
