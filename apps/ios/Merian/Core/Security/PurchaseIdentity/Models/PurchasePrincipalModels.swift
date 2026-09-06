import Foundation

enum PurchasePrincipalResolutionMode: String, Codable, Equatable {
    case legacy
    case stable
}

struct PurchasePrincipalBinding: Codable, Equatable {
    let mode: PurchasePrincipalResolutionMode
    let purchasePrincipalId: UUID?
    let revenueCatAppUserId: String?
    let bindingGeneration: Int64?
    let accountGrantsAllowed: Bool
    let minimumClientProtocol: Int

    var isStable: Bool { mode == .stable }

    private init(
        mode: PurchasePrincipalResolutionMode,
        purchasePrincipalId: UUID?,
        revenueCatAppUserId: String?,
        bindingGeneration: Int64?,
        accountGrantsAllowed: Bool,
        minimumClientProtocol: Int
    ) {
        self.mode = mode
        self.purchasePrincipalId = purchasePrincipalId
        self.revenueCatAppUserId = revenueCatAppUserId
        self.bindingGeneration = bindingGeneration
        self.accountGrantsAllowed = accountGrantsAllowed
        self.minimumClientProtocol = minimumClientProtocol
    }

    init(response: PurchasePrincipalResolveResponse) throws {
        guard response.success,
              response.minimum_client_protocol >= 1,
              response.minimum_client_protocol
                <= PurchasePrincipalProtocol.current else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        guard let mode = PurchasePrincipalResolutionMode(rawValue: response.mode) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        switch mode {
        case .legacy:
            guard response.purchase_principal_id == nil,
                  response.revenuecat_app_user_id == nil,
                  response.binding_generation == nil,
                  response.account_grants_allowed == nil else {
                throw PurchasePrincipalResolverError.invalidResponse
            }
            self.init(
                mode: .legacy,
                purchasePrincipalId: nil,
                revenueCatAppUserId: nil,
                bindingGeneration: nil,
                accountGrantsAllowed: true,
                minimumClientProtocol: response.minimum_client_protocol
            )
        case .stable:
            guard response.minimum_client_protocol
                    >= PurchasePrincipalProtocol.stableMinimum,
                  let principalId = response.purchase_principal_id
                    .flatMap(UUID.init(uuidString:)),
                  let appUserId = response.revenuecat_app_user_id,
                  Self.isValidRevenueCatAppUserId(appUserId),
                  let generation = response.binding_generation,
                  generation > 0,
                  let accountGrantsAllowed = response.account_grants_allowed else {
                throw PurchasePrincipalResolverError.invalidResponse
            }
            self.init(
                mode: .stable,
                purchasePrincipalId: principalId,
                revenueCatAppUserId: appUserId,
                bindingGeneration: generation,
                accountGrantsAllowed: accountGrantsAllowed,
                minimumClientProtocol: response.minimum_client_protocol
            )
        }
    }

    init(signOutRotationClaim response: PrincipalRotationClaimResponse) throws {
        guard response.success,
              response.operation == "claim_signout_rotation",
              response.rotation_status == "completed",
              UUID(uuidString: response.rotation_id) != nil,
              let principalId = UUID(
                uuidString: response.purchase_principal_id
              ),
              Self.isValidRevenueCatAppUserId(
                response.revenuecat_app_user_id
              ),
              response.binding_generation > 0,
              response.account_grants_allowed == false,
              PurchasePrincipalTimestampPolicy.isValidServerTimestamp(
                  response.expires_at
              ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        self.init(
            mode: .stable,
            purchasePrincipalId: principalId,
            revenueCatAppUserId: response.revenuecat_app_user_id,
            bindingGeneration: response.binding_generation,
            accountGrantsAllowed: false,
            minimumClientProtocol: PurchasePrincipalProtocol.current
        )
    }

    static let legacyFallback = PurchasePrincipalBinding(
        mode: .legacy,
        purchasePrincipalId: nil,
        revenueCatAppUserId: nil,
        bindingGeneration: nil,
        accountGrantsAllowed: true,
        minimumClientProtocol: 1
    )

    static func isValidRevenueCatAppUserId(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 255
            && !value.hasPrefix("$RCAnonymousID:")
            && value.unicodeScalars.allSatisfy {
                $0.value > 31 && $0.value != 127
            }
    }

}

enum PurchasePrincipalResolverError: LocalizedError {
    case capabilityUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .capabilityUnavailable:
            return "Purchase identity is unavailable while secure device storage is locked."
        case .invalidResponse:
            return "The purchase identity service returned an invalid response."
        }
    }
}

struct PrincipalRotationPreparation: Equatable {
    let rotationId: UUID
    let purchasePrincipalId: UUID
    let revenueCatAppUserId: String
    let bindingGeneration: Int64
    let expiresAt: String
}

struct PrincipalRotationCancellation: Equatable {
    let rotationId: UUID
    let status: String
    let expiresAt: String
}
