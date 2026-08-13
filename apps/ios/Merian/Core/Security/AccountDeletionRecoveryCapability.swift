import Foundation
import Security

enum AccountDeletionRecoveryCapabilityError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Account deletion recovery is unavailable while secure device storage is locked."
    }
}

protocol AccountDeletionRecoverySecureStore: AnyObject {
    func dataOrThrow(forKey key: String) throws -> Data?

    @discardableResult
    func set(
        _ data: Data,
        forKey key: String,
        accessibility: KeychainManager.Accessibility
    ) -> Bool

    func removeObjectVerified(forKey key: String) throws
}

extension KeychainManager: AccountDeletionRecoverySecureStore {}

struct PreparedDeletionRecoveryCapability: Equatable, Sendable {
    let protocolVersion: Int
    let recoveryValue: String
    let acknowledgementValue: String?
    let wasCreated: Bool

    /// Legacy spelling retained for v1 call sites and fixtures. New deletion
    /// intake uses `recoveryValue` explicitly.
    var value: String { recoveryValue }

    var supportsPreparedCommit: Bool {
        protocolVersion == 2 && acknowledgementValue != nil
    }
}

private struct DeletionRecoveryCapabilityEnvelope:
    Codable, Equatable {
    let protocolVersion: Int
    let recoveryCapability: Data
    let acknowledgementCapability: Data

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case recoveryCapability = "recovery_capability"
        case acknowledgementCapability = "acknowledgement_capability"
    }
}

struct AccountDeletionRecoveryCapabilityStore {
    typealias Generator = () throws -> Data

    private let secureStore: any AccountDeletionRecoverySecureStore
    private let generateCapability: Generator

    init(
        secureStore: any AccountDeletionRecoverySecureStore =
            KeychainManager.shared
    ) {
        self.init(
            secureStore: secureStore,
            generateCapability: Self.generateSecureCapability
        )
    }

    init(
        secureStore: any AccountDeletionRecoverySecureStore,
        generateCapability: @escaping Generator
    ) {
        self.secureStore = secureStore
        self.generateCapability = generateCapability
    }

    func prepare() throws -> PreparedDeletionRecoveryCapability {
        let key = KeychainKeys.accountDeletionRecoveryCapability
        if let existing = try secureStore.dataOrThrow(forKey: key) {
            return try Self.decode(existing, wasCreated: false)
        }

        let recoveryCapability = try generateCapability()
        let acknowledgementCapability = try generateCapability()
        guard recoveryCapability.count == 32,
              acknowledgementCapability.count == 32,
              recoveryCapability != acknowledgementCapability else {
            throw AccountDeletionRecoveryCapabilityError.unavailable
        }
        let envelope = DeletionRecoveryCapabilityEnvelope(
            protocolVersion: 2,
            recoveryCapability: recoveryCapability,
            acknowledgementCapability: acknowledgementCapability
        )
        guard let encoded = try? JSONEncoder().encode(envelope),
              secureStore.set(
                encoded,
                forKey: key,
                accessibility: .whenUnlockedThisDeviceOnly
              ),
              try secureStore.dataOrThrow(forKey: key) == encoded else {
            throw AccountDeletionRecoveryCapabilityError.unavailable
        }
        return PreparedDeletionRecoveryCapability(
            protocolVersion: 2,
            recoveryValue: Self.base64URL(recoveryCapability),
            acknowledgementValue:
                Self.base64URL(acknowledgementCapability),
            wasCreated: true
        )
    }

    func loadExisting() throws -> PreparedDeletionRecoveryCapability {
        guard let capability = try loadExistingIfPresent() else {
            throw AccountDeletionRecoveryCapabilityError.unavailable
        }
        return capability
    }

    func loadExistingIfPresent() throws
        -> PreparedDeletionRecoveryCapability? {
        guard let encoded = try secureStore.dataOrThrow(
            forKey: KeychainKeys.accountDeletionRecoveryCapability
        ) else {
            return nil
        }
        return try Self.decode(encoded, wasCreated: false)
    }

    func loadExistingValue() throws -> String {
        guard let value = try loadExistingValueIfPresent() else {
            throw AccountDeletionRecoveryCapabilityError.unavailable
        }
        return value
    }

    func loadExistingValueIfPresent() throws -> String? {
        guard let encoded = try secureStore.dataOrThrow(
            forKey: KeychainKeys.accountDeletionRecoveryCapability
        ) else {
            return nil
        }
        return try Self.decode(encoded, wasCreated: false).recoveryValue
    }

    func clearVerified() throws {
        try secureStore.removeObjectVerified(
            forKey: KeychainKeys.accountDeletionRecoveryCapability
        )
    }

    /// Runs before `AppDIContainer` starts Auth listeners. Keychain items may
    /// survive reinstall while UserDefaults does not, so a present—or currently
    /// unreadable—proof restores a capability-only barrier. A later successful
    /// absence check removes that conservative barrier without erasing data.
    @MainActor
    static func restoreBarrierBeforeAuthBootstrap(
        secureStore: any AccountDeletionRecoverySecureStore =
            KeychainManager.shared,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard AccountDeletionLocalCleanupStore.state(
            userDefaults: userDefaults
        ) == nil else {
            return true
        }

        do {
            guard try secureStore.dataOrThrow(
                forKey: KeychainKeys.accountDeletionRecoveryCapability
            ) != nil else {
                return true
            }
        } catch {
            // Secure storage uncertainty must be resolved before Auth/session
            // bootstrap; it cannot be interpreted as proof absence.
        }
        return AccountDeletionLocalCleanupStore.recordCapabilityLookupPending(
            userDefaults: userDefaults,
            emitEvent: false
        )
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
            throw AccountDeletionRecoveryCapabilityError.unavailable
        }
        return bytes
    }

    private static func decode(
        _ encoded: Data,
        wasCreated: Bool
    ) throws -> PreparedDeletionRecoveryCapability {
        // Existing clients persisted the raw 32-byte recovery proof. Keep it
        // readable as protocol v1 until the compatibility window closes.
        if encoded.count == 32 {
            return PreparedDeletionRecoveryCapability(
                protocolVersion: 1,
                recoveryValue: base64URL(encoded),
                acknowledgementValue: nil,
                wasCreated: wasCreated
            )
        }
        guard let envelope = try? JSONDecoder().decode(
            DeletionRecoveryCapabilityEnvelope.self,
            from: encoded
        ), envelope.protocolVersion == 2,
              envelope.recoveryCapability.count == 32,
              envelope.acknowledgementCapability.count == 32,
              envelope.recoveryCapability !=
                envelope.acknowledgementCapability else {
            throw AccountDeletionRecoveryCapabilityError.unavailable
        }
        return PreparedDeletionRecoveryCapability(
            protocolVersion: 2,
            recoveryValue: base64URL(envelope.recoveryCapability),
            acknowledgementValue:
                base64URL(envelope.acknowledgementCapability),
            wasCreated: wasCreated
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
