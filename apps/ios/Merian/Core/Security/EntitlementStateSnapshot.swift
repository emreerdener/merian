/// Immutable domain projection of a server entitlement snapshot.
///
/// Wire DTOs stay generator-owned and actor-neutral code carries this value
/// instead of widening generated transport declarations with local protocol
/// conformances.
struct EntitlementStateSnapshot: Sendable {
    let currentPlan: String
    let currentTier: String
    let isPaid: Bool
    let scansRemaining: Int
    let scansAvailableToStart: Int
    let inFlightCount: Int
    let entitlementVersion: Int

    init(_ dto: EntitlementSnapshotDTO) {
        currentPlan = dto.currentPlan
        currentTier = dto.currentTier
        isPaid = dto.isPaid
        scansRemaining = dto.scansRemaining
        scansAvailableToStart = dto.scansAvailableToStart
        inFlightCount = dto.inFlightCount
        entitlementVersion = dto.entitlementVersion
    }
}
