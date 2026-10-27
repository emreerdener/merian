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

    private(set) var state: State = .closed
    private let ownerID: UUID
    private let isCurrent: () -> Bool
    private let discover: () async throws -> [Candidate]
    private var presentation = UUID()
    private var profile: SharedMediaNativeAppProfile?

    /// isCurrent binds the caller's account, container and lifetime generation.
    /// The existing native owner independently checks its retained dispatch grant.
    init(ownerID: UUID, isCurrent: @escaping () -> Bool,
         discover: @escaping () async throws -> [Candidate]) {
        self.ownerID = ownerID; self.isCurrent = isCurrent; self.discover = discover
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
    /// No durable lifecycle command or owner shutdown is issued here.
    func close() {
        presentation = UUID()
        profile = nil
        state = .closed
    }

    private func read(selected: Candidate?) async {
        guard state != .checking else { return }
        guard isCurrent(), !Task.isCancelled else { state = .unavailable; return }
        let token = presentation
        state = .checking
        do {
            let candidates = try await discover()
            guard presentation == token else { return }
            guard isCurrent(), !Task.isCancelled,
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
