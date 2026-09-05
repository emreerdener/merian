import Foundation

/// Device-bound capability that authorizes one provider-bound guest-profile
/// merge after the permanent provider session replaces the guest session.
struct PendingGhostProfileMerge: Codable, Equatable, Sendable {
    let ghostUserId: String
    let provider: String
    let providerSubject: String
    let handoffId: String
    let handoffSecret: String
    let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case ghostUserId
        case provider
        case providerSubject
        case handoffId
        case handoffSecret
        case expiresAt
    }
}

/// Versioned envelope introduced after the original single-record format.
/// The store still decodes and migrates that legacy shape in place.
struct PendingGhostProfileMergeQueue: Codable, Equatable, Sendable {
    let version: Int
    let handoffs: [PendingGhostProfileMerge]

    init(handoffs: [PendingGhostProfileMerge]) {
        self.version = 1
        self.handoffs = handoffs
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case handoffs
    }
}
