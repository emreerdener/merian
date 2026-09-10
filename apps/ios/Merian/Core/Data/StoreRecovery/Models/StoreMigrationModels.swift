import Foundation

extension ModelStoreRecoveryCoordinator {
    /// Installed schema versions with explicit source-isolated startup plans.
    ///
    /// Keep these cases consecutive and end at the schema immediately before
    /// `CurrentSchema`. The app switches over this enum exhaustively, so adding
    /// a future predecessor requires its dedicated runtime plan at compile time.
    enum RecentSourceSchema: Int, CaseIterable, Equatable {
        case v42 = 42
        case v43 = 43
        case v44 = 44
        case v45 = 45
        case v46 = 46
        case v47 = 47
        case v48 = 48
        case v49 = 49
        case v50 = 50
    }

    /// V50 was shipped with two distinct model graphs under the same schema
    /// version. The store checksum, not the shared major version, determines
    /// which immutable source schema can open it safely.
    enum V50StoreVariant: Equatable, CustomStringConvertible {
        case frozenSnapshot
        case releasedActive
        case unknown

        var description: String {
            switch self {
            case .frozenSnapshot:
                return "frozen-snapshot"
            case .releasedActive:
                return "released-active"
            case .unknown:
                return "unknown-model"
            }
        }
    }

    enum StoreMigrationHint: Equatable, CustomStringConvertible {
        case currentStore
        case recentSource(RecentSourceSchema)
        case fullHistorical

        var description: String {
            switch self {
            case .currentStore:
                return "current-store"
            case let .recentSource(source):
                return "recent-source-v\(source.rawValue)"
            case .fullHistorical:
                return "full-historical"
            }
        }
    }

    struct StoreMigrationDecision: Equatable {
        let hasStoreArtifacts: Bool
        let storedSchemaMajorVersion: Int?
        let hint: StoreMigrationHint
        let v50StoreVariant: V50StoreVariant?

        init(
            hasStoreArtifacts: Bool,
            storedSchemaMajorVersion: Int?,
            hint: StoreMigrationHint,
            v50StoreVariant: V50StoreVariant? = nil
        ) {
            self.hasStoreArtifacts = hasStoreArtifacts
            self.storedSchemaMajorVersion = storedSchemaMajorVersion
            self.hint = hint
            self.v50StoreVariant = v50StoreVariant
        }

        var strategyDescription: String {
            guard case .recentSource(.v50) = hint else {
                return hint.description
            }
            return "\(hint.description)-\((v50StoreVariant ?? .unknown).description)"
        }
    }
}

struct ModelStoreSafeModeFallback: Equatable {
    let message: String
    let telemetryReason: String
}
