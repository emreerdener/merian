import CryptoKit
import Foundation
import Security
import Supabase

private enum PurchasePrincipalProtocol {
    /// Protocol 3 adds server-authorized stable sign-out rotations. Protocol 2
    /// stable responses remain readable during the additive rollout, but new
    /// stable activation is release-gated on protocol 3.
    static let current = 3
    static let stableMinimum = 2
}

enum PurchasePrincipalCapabilityPolicy {
    static func fingerprint(_ capability: Data) -> String {
        SHA256.hash(data: capability)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func isValidFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

enum PurchasePrincipalBindingIntentPolicy {
    // JSON crosses Deno/JavaScript before Postgres. Keep the durable counter in
    // the exact-integer range shared by all three runtimes.
    static let maximum = Int64(9_007_199_254_740_991)

    static func next(after current: Int64) throws -> Int64 {
        guard current >= 0, current < maximum else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return current + 1
    }
}

enum PurchasePrincipalResolutionMode: String, Codable, Equatable {
    case legacy
    case stable
}

enum PurchasePrincipalCompatibilityPolicy {
    static func allowsLegacyFallback(hasStableActivation: Bool) -> Bool {
        !hasStableActivation
    }
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
              Self.isValidServerTimestamp(response.expires_at) else {
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

    static func isValidServerTimestamp(_ value: String) -> Bool {
        ISO8601DateFormatter().date(from: value) != nil
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

protocol PurchasePrincipalSecureStore: AnyObject {
    func dataOrThrow(forKey key: String) throws -> Data?

    @discardableResult
    func set(
        _ data: Data,
        forKey key: String,
        accessibility: KeychainManager.Accessibility
    ) -> Bool
}

extension KeychainManager: PurchasePrincipalSecureStore {}

struct PurchasePrincipalCapabilityStore {
    typealias Generator = () throws -> Data

    private let secureStore: any PurchasePrincipalSecureStore
    private let generateCapability: Generator

    init(
        secureStore: any PurchasePrincipalSecureStore
    ) {
        self.init(
            secureStore: secureStore,
            generateCapability: Self.generateSecureCapability
        )
    }

    init(
        secureStore: any PurchasePrincipalSecureStore,
        generateCapability: @escaping Generator
    ) {
        self.secureStore = secureStore
        self.generateCapability = generateCapability
    }

    func loadExisting() throws -> Data {
        guard let capability = try secureStore.dataOrThrow(
            forKey: KeychainKeys.purchasePrincipalInstallationCapability
        ), capability.count == 32 else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return capability
    }

    func loadOrCreate(allowsCreation: Bool) throws -> Data {
        let key = KeychainKeys.purchasePrincipalInstallationCapability
        if let existing = try secureStore.dataOrThrow(forKey: key) {
            guard existing.count == 32 else {
                throw PurchasePrincipalResolverError.capabilityUnavailable
            }
            return existing
        }
        guard allowsCreation else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }

        let capability = try generateCapability()
        guard capability.count == 32,
              secureStore.set(
                capability,
                forKey: key,
                accessibility: .whenUnlockedThisDeviceOnly
              ),
              try secureStore.dataOrThrow(forKey: key) == capability else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return capability
    }

    private static func generateSecureCapability() throws -> Data {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }
        guard status == errSecSuccess else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return bytes
    }
}

private struct PurchasePrincipalResolvePayload: Encodable {
    let operation = "resolve"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let binding_intent_generation: Int64
}

private struct PrincipalRotationPreparePayload: Encodable {
    let operation = "prepare_signout_rotation"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let rotation_id: String
    let rotation_secret: String
    let expected_binding_generation: Int64
}

private struct PrincipalRotationClaimPayload: Encodable {
    let operation = "claim_signout_rotation"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let rotation_id: String
    let rotation_secret: String
}

private struct PrincipalRotationCancelPayload: Encodable {
    let operation = "cancel_signout_rotation"
    let installation_capability: String
    let client_protocol = PurchasePrincipalProtocol.current
    let rotation_id: String
    let rotation_secret: String
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

@MainActor
final class PurchasePrincipalResolver {
    private let client: SupabaseClient
    private let keychain: any PurchasePrincipalSecureStore
    private let capabilityStore: PurchasePrincipalCapabilityStore

    init(
        client: SupabaseClient,
        keychain: any PurchasePrincipalSecureStore = KeychainManager.shared
    ) {
        self.client = client
        self.keychain = keychain
        capabilityStore = PurchasePrincipalCapabilityStore(
            secureStore: keychain
        )
    }

    func resolve(
        expectedCapabilityFingerprint: String? = nil,
        allowsCapabilityCreation: Bool = true
    ) async throws -> PurchasePrincipalBinding {
        let stableActivationFingerprint = try loadStableActivationFingerprint()
        let capabilityData = try capabilityStore.loadOrCreate(
            allowsCreation:
                allowsCapabilityCreation && stableActivationFingerprint == nil
        )
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capabilityData
        )
        guard expectedCapabilityFingerprint.map({ $0 == fingerprint }) ?? true else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        guard stableActivationFingerprint.map({ $0 == fingerprint }) ?? true else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        let capability = Self.base64URL(capabilityData)
        let bindingIntentGeneration = try advanceBindingIntentGeneration(
            requiresExisting: stableActivationFingerprint != nil
        )
        do {
            let response: PurchasePrincipalResolveResponse = try await client.functions.invoke(
                "resolve-purchase-principal",
                options: .init(
                    body: PurchasePrincipalResolvePayload(
                        installation_capability: capability,
                        binding_intent_generation: bindingIntentGeneration
                    )
                )
            )
            let binding = try PurchasePrincipalBinding(response: response)
            switch binding.mode {
            case .legacy:
                guard PurchasePrincipalCompatibilityPolicy
                    .allowsLegacyFallback(
                        hasStableActivation:
                            stableActivationFingerprint != nil
                    ) else {
                    throw PurchasePrincipalResolverError.invalidResponse
                }
            case .stable:
                try persistStableActivationFingerprint(fingerprint)
            }
            return binding
        } catch let error as FunctionsError {
            guard Self.isUnsupportedRoute(error),
                  PurchasePrincipalCompatibilityPolicy
                    .allowsLegacyFallback(
                        hasStableActivation:
                            stableActivationFingerprint != nil
                    ) else {
                throw error
            }
            // New clients can roll out before the additive backend route. Only
            // a definite missing route falls back; every transient/auth/service
            // failure remains fail-closed.
            return .legacyFallback
        }
    }

    static func generateSignoutRotationSecret() throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }
        guard status == errSecSuccess else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return base64URL(bytes)
    }

    func prepareSignoutRotation(
        rotationId: UUID,
        rotationSecret: String,
        expectedBinding: PurchasePrincipalBinding,
        expectedCapabilityFingerprint: String
    ) async throws -> PrincipalRotationPreparation {
        guard expectedBinding.mode == .stable,
              let expectedPrincipalId = expectedBinding.purchasePrincipalId,
              let expectedAppUserId = expectedBinding.revenueCatAppUserId,
              let expectedGeneration = expectedBinding.bindingGeneration,
              expectedGeneration > 0,
              Self.isValidRotationSecret(rotationSecret) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        let capability = try activatedInstallationCapability(
            expectedFingerprint: expectedCapabilityFingerprint
        )
        let response: PrincipalRotationPrepareResponse =
            try await client.functions.invoke(
                "resolve-purchase-principal",
                options: .init(
                    body: PrincipalRotationPreparePayload(
                        installation_capability: capability,
                        rotation_id: rotationId.uuidString.lowercased(),
                        rotation_secret: rotationSecret,
                        expected_binding_generation: expectedGeneration
                    )
                )
            )
        guard response.success,
              response.operation == "prepare_signout_rotation",
              response.rotation_status == "prepared",
              let responseRotationId = UUID(uuidString: response.rotation_id),
              responseRotationId == rotationId,
              let responsePrincipalId = UUID(
                uuidString: response.purchase_principal_id
              ),
              responsePrincipalId == expectedPrincipalId,
              response.revenuecat_app_user_id == expectedAppUserId,
              response.binding_generation == expectedGeneration,
              PurchasePrincipalBinding.isValidRevenueCatAppUserId(
                response.revenuecat_app_user_id
              ),
              PurchasePrincipalBinding.isValidServerTimestamp(
                response.expires_at
              ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        return PrincipalRotationPreparation(
            rotationId: responseRotationId,
            purchasePrincipalId: responsePrincipalId,
            revenueCatAppUserId: response.revenuecat_app_user_id,
            bindingGeneration: response.binding_generation,
            expiresAt: response.expires_at
        )
    }

    func claimSignoutRotation(
        rotationId: UUID,
        rotationSecret: String,
        expectedCapabilityFingerprint: String
    ) async throws -> PurchasePrincipalBinding {
        guard Self.isValidRotationSecret(rotationSecret) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        let capability = try activatedInstallationCapability(
            expectedFingerprint: expectedCapabilityFingerprint
        )
        let response: PrincipalRotationClaimResponse =
            try await client.functions.invoke(
                "resolve-purchase-principal",
                options: .init(
                    body: PrincipalRotationClaimPayload(
                        installation_capability: capability,
                        rotation_id: rotationId.uuidString.lowercased(),
                        rotation_secret: rotationSecret
                    )
                )
            )
        guard UUID(uuidString: response.rotation_id) == rotationId else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        return try PurchasePrincipalBinding(signOutRotationClaim: response)
    }

    func cancelSignoutRotation(
        rotationId: UUID,
        rotationSecret: String,
        expectedCapabilityFingerprint: String
    ) async throws -> PrincipalRotationCancellation {
        guard Self.isValidRotationSecret(rotationSecret) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        let capability = try activatedInstallationCapability(
            expectedFingerprint: expectedCapabilityFingerprint
        )
        let response: PrincipalRotationCancelResponse =
            try await client.functions.invoke(
                "resolve-purchase-principal",
                options: .init(
                    body: PrincipalRotationCancelPayload(
                        installation_capability: capability,
                        rotation_id: rotationId.uuidString.lowercased(),
                        rotation_secret: rotationSecret
                    )
                )
            )
        guard response.success,
              response.operation == "cancel_signout_rotation",
              let responseRotationId = UUID(uuidString: response.rotation_id),
              responseRotationId == rotationId,
              ["cancelled", "expired"].contains(response.rotation_status),
              PurchasePrincipalBinding.isValidServerTimestamp(
                response.expires_at
              ) else {
            throw PurchasePrincipalResolverError.invalidResponse
        }
        return PrincipalRotationCancellation(
            rotationId: responseRotationId,
            status: response.rotation_status,
            expiresAt: response.expires_at
        )
    }

    func currentInstallationCapabilityFingerprint() throws -> String {
        let capability = try capabilityStore.loadExisting()
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capability
        )
        guard try loadStableActivationFingerprint().map({
            $0 == fingerprint
        }) ?? true else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return fingerprint
    }

    private func activatedInstallationCapability(
        expectedFingerprint: String
    ) throws -> String {
        guard PurchasePrincipalCapabilityPolicy.isValidFingerprint(
            expectedFingerprint
        ) else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        let capability = try capabilityStore.loadExisting()
        let fingerprint = PurchasePrincipalCapabilityPolicy.fingerprint(
            capability
        )
        guard fingerprint == expectedFingerprint,
              try loadStableActivationFingerprint() == fingerprint else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return Self.base64URL(capability)
    }

    private func loadStableActivationFingerprint() throws -> String? {
        guard let data = try keychain.dataOrThrow(
            forKey: KeychainKeys.purchasePrincipalStableActivationFingerprint
        ) else {
            return nil
        }
        guard let fingerprint = String(data: data, encoding: .utf8),
              PurchasePrincipalCapabilityPolicy.isValidFingerprint(
                fingerprint
              ) else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return fingerprint
    }

    private func persistStableActivationFingerprint(
        _ fingerprint: String
    ) throws {
        if let existing = try loadStableActivationFingerprint() {
            guard existing == fingerprint else {
                throw PurchasePrincipalResolverError.capabilityUnavailable
            }
            return
        }
        let data = Data(fingerprint.utf8)
        guard keychain.set(
            data,
            forKey: KeychainKeys.purchasePrincipalStableActivationFingerprint,
            accessibility: .whenUnlockedThisDeviceOnly
        ),
        try keychain.dataOrThrow(
            forKey: KeychainKeys.purchasePrincipalStableActivationFingerprint
        ) == data else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
    }

    private func advanceBindingIntentGeneration(
        requiresExisting: Bool
    ) throws -> Int64 {
        let key = KeychainKeys.purchasePrincipalBindingIntentGeneration
        let current: Int64
        if let data = try keychain.dataOrThrow(forKey: key) {
            guard let value = String(data: data, encoding: .utf8),
                  let parsed = Int64(value),
                  parsed >= 0,
                  String(parsed) == value else {
                throw PurchasePrincipalResolverError.capabilityUnavailable
            }
            current = parsed
        } else if requiresExisting {
            // Once stable mode has activated, losing only the ordering record
            // is uncertainty. Never reset it to one and risk replaying an old
            // Auth binding against a higher server generation.
            throw PurchasePrincipalResolverError.capabilityUnavailable
        } else {
            current = 0
        }
        let next = try PurchasePrincipalBindingIntentPolicy.next(after: current)
        let encoded = Data(String(next).utf8)
        guard keychain.set(
            encoded,
            forKey: key,
            accessibility: .whenUnlockedThisDeviceOnly
        ), try keychain.dataOrThrow(forKey: key) == encoded else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return next
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isValidRotationSecret(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isUnsupportedRoute(_ error: FunctionsError) -> Bool {
        guard case let .httpError(status, _) = error else { return false }
        return status == 404
    }
}
