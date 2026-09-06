import Foundation

enum PurchasePrincipalProtocol {
    /// Protocol 3 adds server-authorized stable sign-out rotations. Protocol 2
    /// stable responses remain readable during the additive rollout, but new
    /// stable activation is release-gated on protocol 3.
    static let current = 3
    static let stableMinimum = 2
}

struct PurchasePrincipalResolveResponse: Decodable {
    let success: Bool
    let mode: String
    let purchase_principal_id: String?
    let revenuecat_app_user_id: String?
    let binding_generation: Int64?
    let account_grants_allowed: Bool?
    let minimum_client_protocol: Int
}

struct PrincipalRotationPrepareResponse: Decodable {
    let success: Bool
    let operation: String
    let rotation_id: String
    let rotation_status: String
    let expires_at: String
    let purchase_principal_id: String
    let revenuecat_app_user_id: String
    let binding_generation: Int64
    let already_prepared: Bool
}

struct PrincipalRotationClaimResponse: Decodable {
    let success: Bool
    let operation: String
    let rotation_id: String
    let rotation_status: String
    let expires_at: String
    let purchase_principal_id: String
    let revenuecat_app_user_id: String
    let binding_generation: Int64
    let account_grants_allowed: Bool
    let already_claimed: Bool
}

struct PrincipalRotationCancelResponse: Decodable {
    let success: Bool
    let operation: String
    let rotation_id: String
    let rotation_status: String
    let expires_at: String
    let already_cancelled: Bool
}
