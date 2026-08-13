import CryptoKit
import Foundation
import Security
import Supabase

private enum PurchasePrincipalProtocol {
    /// Protocol 2 is the first client contract eligible for stable-principal
    /// activation. Protocol 1 remains server-supported only for the additive
    /// legacy compatibility window.
    static let current = 2
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

struct PurchasePrincipalResolveResponse: Decodable {
    let success: Bool
    let mode: String
    let purchase_principal_id: String?
    let revenuecat_app_user_id: String?
    let binding_generation: Int64?
    let account_grants_allowed: Bool?
    let minimum_client_protocol: Int
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

    private static func isUnsupportedRoute(_ error: FunctionsError) -> Bool {
        guard case let .httpError(status, _) = error else { return false }
        return status == 404
    }
}
