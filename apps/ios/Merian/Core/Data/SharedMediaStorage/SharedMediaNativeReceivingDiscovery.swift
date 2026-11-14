import Foundation

/// Exact local holding identity only. No media access, editable draft or
/// execution capability is represented by this value.
struct SharedMediaNativeReceivedCandidate: Equatable, Sendable {
    let profile: SharedMediaNativeAppProfile
    let packageID: UUID
    let draftGeneration: UUID
    let operationID: UUID
    let revision: Int64
    let preparedSHA256: String
    let receivedSHA256: String
}

@MainActor
enum SharedMediaNativeReceivingDiscovery {
    /// The repository retains the private grant/root checks. Fresh facts are
    /// read only after the complete audit, and cannot escape a changed header.
    static func read<T: Sendable>(check: () throws -> SharedMediaNativeAppEligibility.Header,
                                  inspect: () async throws -> Void,
                                  facts: () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let expected = try check()
        try await inspect()
        try Task.checkCancellation()
        guard try check() == expected else { throw SharedMediaStorageFailure.stale }
        let result = try facts()
        try Task.checkCancellation()
        guard try check() == expected else { throw SharedMediaStorageFailure.stale }
        return result
    }
}
