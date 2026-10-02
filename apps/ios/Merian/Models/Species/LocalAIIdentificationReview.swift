import Foundation

/// Pending intent is kept separate from server revision authority.
struct LocalAIIdentificationReview: Codable, Equatable, Sendable {
    var authority: AIIdentificationReview?
    var pending: AIIdentificationReviewRequest?
    var optimisticState: AIIdentificationReview.State?
    var needsAttention: Bool = false
    var conflictReconciled: Bool?
    var state: AIIdentificationReview.State {
        if let optimisticState { return optimisticState }
        // Acceptance cannot confer species authority until acknowledged.
        return authority?.state ?? .clear
    }
    var community: AIIdentificationReview.Community? { isUnresolved ? nil : authority?.community }
    var isUnresolved: Bool { state != .clear }
    func storedData() throws -> Data { try JSONEncoder().encode(self) }
    static func restoring(_ data: Data?) -> Self {
        guard let data else { return Self() }
        guard let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(authority: .init(revision: 0, state: .awaitingAcceptance, originScanID: nil, originIdentification: nil), needsAttention: true)
        }
        return value
    }
}
