import Foundation

/// Structural classification only. Direct ownership still requires a fresh ledger join.
/// Missing or malformed shared authority never returns a legacy projection.
enum SharedMediaConsumerAuthority: Equatable, Sendable {
    case legacy
    case direct(UUID)
    case nativeDirect(UUID)
    case nativeInitial(UUID)
    case historyProjection

    enum RecordKind: Equatable, Sendable { case queue, scan, analysis }

    /// Negative guard for legacy cleanup only. A true value still requires the
    /// current reverse-owner query and the existing account/deletion fences.
    static func permitsLegacyScanRemoval(raw: String, consumerID: UUID?) -> Bool {
        switch try? classify(raw: raw, consumerID: consumerID, record: .scan) {
        case .legacy, .historyProjection: return true
        default: return false
        }
    }

    static func classify(raw: String, consumerID: UUID?, record: RecordKind) throws -> Self {
        switch (raw, consumerID) {
        case ("legacy", nil): return .legacy
        case let ("sharedDirectV1", .some(id)): return .direct(id)
        case let ("sharedDirectNativeReceivingV1", .some(id)): return .nativeDirect(id)
        case let ("sharedDirectNativeInitialV1", .some(id)) where record == .scan: return .nativeInitial(id)
        case ("sharedHistoryProjectionV1", nil) where record == .scan: return .historyProjection
        default: throw SharedMediaStorageFailure.conflict
        }
    }
}

/// Execution identity survives ownership transfer (initial scan to baseline child).
/// Reanalysis uses its existing intent/attempt/erasure authority, not an initial generation.
enum SharedMediaConsumerExecution: Equatable, Sendable {
    case ordinary(UUID)
    case reanalysis

    static func classify(raw: String, generation: UUID?) throws -> Self {
        switch (raw, generation) {
        case let ("ordinaryV1", .some(value)): return .ordinary(value)
        case ("reanalysisV1", nil): return .reanalysis
        default: throw SharedMediaStorageFailure.conflict
        }
    }
}
