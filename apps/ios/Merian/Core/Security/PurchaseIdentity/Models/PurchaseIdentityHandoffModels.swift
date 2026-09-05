import Foundation

struct PendingSignOutPurchaseHandoff: Codable, Equatable {
    let sourceUserId: String
    let handoffId: String
    let handoffSecret: String
    let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case sourceUserId
        case handoffId
        case handoffSecret
        case expiresAt
    }
}

struct LegacyPrincipalRotation: Codable, Equatable {
    let sourceUserId: String
    let purchasePrincipalId: String
    let revenueCatAppUserId: String
    let installationCapabilityFingerprint: String
    let startedAt: String

    private enum CodingKeys: String, CodingKey {
        case sourceUserId
        case purchasePrincipalId
        case revenueCatAppUserId
        case installationCapabilityFingerprint
        case startedAt
    }
}

enum PrincipalRotationLocalState: String, Codable {
    case preparing
    case prepared
}

struct ServerPrincipalRotation: Codable, Equatable {
    let protocolVersion: Int
    let localState: PrincipalRotationLocalState
    let rotationId: String
    let rotationSecret: String
    let sourceUserId: String
    let purchasePrincipalId: String
    let revenueCatAppUserId: String
    let bindingGeneration: Int64
    let installationCapabilityFingerprint: String
    let startedAt: String
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case localState
        case rotationId
        case rotationSecret
        case sourceUserId
        case purchasePrincipalId
        case revenueCatAppUserId
        case bindingGeneration
        case installationCapabilityFingerprint
        case startedAt
        case expiresAt
    }
}

enum PendingPurchasePrincipalAuthRotation: Equatable {
    case legacy(LegacyPrincipalRotation)
    case server(ServerPrincipalRotation)

    var sourceUserId: String {
        switch self {
        case let .legacy(rotation): rotation.sourceUserId
        case let .server(rotation): rotation.sourceUserId
        }
    }

    var purchasePrincipalId: String {
        switch self {
        case let .legacy(rotation): rotation.purchasePrincipalId
        case let .server(rotation): rotation.purchasePrincipalId
        }
    }

    var revenueCatAppUserId: String {
        switch self {
        case let .legacy(rotation): rotation.revenueCatAppUserId
        case let .server(rotation): rotation.revenueCatAppUserId
        }
    }

    var installationCapabilityFingerprint: String {
        switch self {
        case let .legacy(rotation):
            rotation.installationCapabilityFingerprint
        case let .server(rotation):
            rotation.installationCapabilityFingerprint
        }
    }
}
