import Foundation

enum AccountDeletionRecoveryCapabilityError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Account deletion recovery is unavailable while secure device storage is locked."
    }
}

struct PreparedDeletionRecoveryCapability: Equatable, Sendable {
    let protocolVersion: Int
    let recoveryValue: String
    let acknowledgementValue: String?
    let wasCreated: Bool

    /// Legacy spelling retained for v1 call sites and fixtures. New deletion
    /// intake uses `recoveryValue` explicitly.
    var value: String { recoveryValue }

    var supportsPreparedCommit: Bool {
        protocolVersion == 2 && acknowledgementValue != nil
    }
}
