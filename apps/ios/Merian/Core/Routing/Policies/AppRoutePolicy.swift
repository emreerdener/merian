import Foundation

extension AppRoute {
    func coalesces(with other: AppRoute) -> Bool {
        switch (self, other) {
        case (.proAccessRequired, .proAccessRequired),
             (.fieldTrips, .fieldTrips),
             (.recallLastFind, .recallLastFind),
             (.nonBiologicalScans, .nonBiologicalScans),
             (.scansLibrary, .scansLibrary),
             (.processExternalImageImports, .processExternalImageImports),
             (.externalImageImportFailed, .externalImageImportFailed):
            return true
        case let (.scan(lhs), .scan(rhs)),
             let (.speciesDictionary(lhs), .speciesDictionary(rhs)),
             let (.communityIdentification(lhs), .communityIdentification(rhs)):
            return Self.normalizedIdentifier(lhs) ==
                Self.normalizedIdentifier(rhs)
        case let (
            .explorePost(lhsPost, lhsComment, lhsReply),
            .explorePost(rhsPost, rhsComment, rhsReply)
        ):
            return Self.normalizedIdentifier(lhsPost) ==
                Self.normalizedIdentifier(rhsPost)
                && Self.normalizedIdentifier(lhsComment) ==
                Self.normalizedIdentifier(rhsComment)
                && Self.normalizedIdentifier(lhsReply) ==
                Self.normalizedIdentifier(rhsReply)
        case (.identifyNature, .openScanner), (.openScanner, .identifyNature):
            return true
        case (.identifyNature, .identifyNature), (.openScanner, .openScanner):
            return true
        case let (.achievement(lhs), .achievement(rhs)):
            return lhs.id == rhs.id
        case let (.captureGoal(lhs), .captureGoal(rhs)):
            return lhs == rhs
        case let (
            .refinement(lhsScanID, _, lhsEntryPoint),
            .refinement(rhsScanID, _, rhsEntryPoint)
        ):
            return Self.normalizedIdentifier(lhsScanID) ==
                Self.normalizedIdentifier(rhsScanID)
                && lhsEntryPoint == rhsEntryPoint
        case let (.scansLibraryRecovery(lhs), .scansLibraryRecovery(rhs)):
            return Self.normalizedIdentifier(lhs.ownerUserId) ==
                Self.normalizedIdentifier(rhs.ownerUserId)
        #if DEBUG
        case (.debugPreviewAnalyzing, .debugPreviewAnalyzing):
            return true
        #endif
        default:
            return false
        }
    }

    var isAccountSensitive: Bool {
        switch self {
        case .scan, .communityIdentification, .achievement, .captureGoal,
             .fieldTrips, .recallLastFind, .refinement, .nonBiologicalScans,
             .scansLibrary, .scansLibraryRecovery, .proAccessRequired:
            return true
        case .explorePost, .speciesDictionary, .identifyNature, .openScanner,
             .processExternalImageImports, .externalImageImportFailed:
            return false
        #if DEBUG
        case .debugPreviewAnalyzing:
            return false
        #endif
        }
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        value.map { normalizedIdentifier($0) }
    }
}

extension AppRouteSource {
    var priority: AppRoutePriority {
        switch self {
        case .durableExternalImport: .durableExternalImport
        case .deepLink, .pushNotification, .appIntent: .explicitExternal
        case .internalUserAction: .internalUserAction
        case .genericLaunch: .genericLaunch
        case .debug: .debug
        }
    }

    var lifetime: TimeInterval? {
        switch self {
        case .durableExternalImport:
            return nil
        case .deepLink, .pushNotification:
            return 5 * 60
        case .appIntent:
            return 2 * 60
        case .internalUserAction:
            return 30
        case .genericLaunch:
            return 15
        case .debug:
            return 30
        }
    }

    var survivesSessionReset: Bool {
        switch self {
        case .durableExternalImport, .deepLink, .pushNotification, .appIntent:
            return true
        case .internalUserAction, .genericLaunch, .debug:
            return false
        }
    }
}

extension AppRouteOutcome {
    var isTerminal: Bool {
        switch self {
        case .applied(let presentationID):
            return presentationID == nil
        case .dismissed, .rejected:
            return true
        case .deferred:
            return false
        }
    }
}
