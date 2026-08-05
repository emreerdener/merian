import Foundation

protocol ConsentLedgerStoring: AnyObject {
    func loadLedgerData() throws -> Data?
    func saveLedgerData(_ data: Data) throws
    func loadAnalyticsRevocationIntentData() throws -> Data?
    func saveAnalyticsRevocationIntentData(_ data: Data) throws
    func clearAnalyticsRevocationIntentData() throws
}

enum ConsentLedgerStorageError: LocalizedError {
    case ledgerReadFailed
    case ledgerWriteFailed
    case ledgerVerificationFailed
    case legacyLedgerRemovalFailed
    case revocationIntentReadFailed
    case revocationIntentWriteFailed
    case revocationIntentVerificationFailed

    var errorDescription: String? {
        switch self {
        case .ledgerReadFailed:
            return "The consent record could not be read."
        case .ledgerWriteFailed:
            return "The consent record could not be saved."
        case .ledgerVerificationFailed:
            return "The saved consent record could not be verified."
        case .legacyLedgerRemovalFailed:
            return "The previous consent record could not be retired safely."
        case .revocationIntentReadFailed:
            return "The analytics withdrawal safeguard could not be read."
        case .revocationIntentWriteFailed:
            return "The analytics withdrawal safeguard could not be saved."
        case .revocationIntentVerificationFailed:
            return "The analytics withdrawal safeguard could not be verified."
        }
    }
}

/// Production storage for the append-only consent ledger.
///
/// The ledger uses an atomically replaced, read-back-verified file. Analytics
/// withdrawal first writes a small journal to Keychain, which is an independent
/// durable boundary. If the larger file write fails, the journal keeps capture
/// disabled across launches and can be replayed later without changing event
/// IDs or timestamps.
final class DurableConsentLedgerStore: ConsentLedgerStoring {
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let applicationSupportDirectory: URL?
    private let keychainManager: KeychainManager

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        applicationSupportDirectory: URL? = nil,
        keychainManager: KeychainManager = .shared
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.applicationSupportDirectory = applicationSupportDirectory
        self.keychainManager = keychainManager
    }

    func loadLedgerData() throws -> Data? {
        let url: URL
        do {
            url = try ledgerURL()
        } catch {
            throw ConsentLedgerStorageError.ledgerReadFailed
        }

        if fileManager.fileExists(atPath: url.path) {
            do {
                return try Data(contentsOf: url)
            } catch {
                throw ConsentLedgerStorageError.ledgerReadFailed
            }
        }

        guard let legacyData = userDefaults.data(
            forKey: UserDefaultsKeys.legalConsentLedger
        ) else {
            return nil
        }

        try saveLedgerData(legacyData)
        return legacyData
    }

    func saveLedgerData(_ data: Data) throws {
        let url: URL
        do {
            url = try ledgerURL()
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            throw ConsentLedgerStorageError.ledgerWriteFailed
        }

        guard (try? Data(contentsOf: url)) == data else {
            throw ConsentLedgerStorageError.ledgerVerificationFailed
        }

        // The file is authoritative only after its contents were verified.
        // Removing the old defaults copy prevents a downgrade from reopening
        // analytics using a stale grant.
        userDefaults.removeObject(forKey: UserDefaultsKeys.legalConsentLedger)
        guard userDefaults.data(forKey: UserDefaultsKeys.legalConsentLedger) == nil else {
            throw ConsentLedgerStorageError.legacyLedgerRemovalFailed
        }
    }

    func loadAnalyticsRevocationIntentData() throws -> Data? {
        do {
            return try keychainManager.dataOrThrow(
                forKey: KeychainKeys.analyticsRevocationIntent
            )
        } catch {
            throw ConsentLedgerStorageError.revocationIntentReadFailed
        }
    }

    func saveAnalyticsRevocationIntentData(_ data: Data) throws {
        guard keychainManager.set(
            data,
            forKey: KeychainKeys.analyticsRevocationIntent,
            accessibility: .afterFirstUnlockThisDeviceOnly
        ) else {
            throw ConsentLedgerStorageError.revocationIntentWriteFailed
        }

        do {
            guard try keychainManager.dataOrThrow(
                forKey: KeychainKeys.analyticsRevocationIntent
            ) == data else {
                throw ConsentLedgerStorageError.revocationIntentVerificationFailed
            }
        } catch let error as ConsentLedgerStorageError {
            throw error
        } catch {
            throw ConsentLedgerStorageError.revocationIntentVerificationFailed
        }
    }

    func clearAnalyticsRevocationIntentData() throws {
        do {
            try keychainManager.removeObjectVerified(
                forKey: KeychainKeys.analyticsRevocationIntent
            )
        } catch {
            throw ConsentLedgerStorageError.revocationIntentVerificationFailed
        }
    }

    private func ledgerURL() throws -> URL {
        let root: URL
        if let applicationSupportDirectory {
            root = applicationSupportDirectory
        } else {
            root = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        return root
            .appendingPathComponent("Naturebook", isDirectory: true)
            .appendingPathComponent("Consent", isDirectory: true)
            .appendingPathComponent("ledger-v1.json", isDirectory: false)
    }
}

/// Compatibility store used by tests that already isolate a UserDefaults
/// suite. Production uses `DurableConsentLedgerStore`.
final class UserDefaultsConsentLedgerStore: ConsentLedgerStoring {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func loadLedgerData() throws -> Data? {
        userDefaults.data(forKey: UserDefaultsKeys.legalConsentLedger)
    }

    func saveLedgerData(_ data: Data) throws {
        userDefaults.set(data, forKey: UserDefaultsKeys.legalConsentLedger)
        guard userDefaults.data(forKey: UserDefaultsKeys.legalConsentLedger) == data else {
            throw ConsentLedgerStorageError.ledgerVerificationFailed
        }
    }

    func loadAnalyticsRevocationIntentData() throws -> Data? {
        userDefaults.data(
            forKey: UserDefaultsKeys.analyticsRevocationIntent
        )
    }

    func saveAnalyticsRevocationIntentData(_ data: Data) throws {
        userDefaults.set(
            data,
            forKey: UserDefaultsKeys.analyticsRevocationIntent
        )
        guard userDefaults.data(
            forKey: UserDefaultsKeys.analyticsRevocationIntent
        ) == data else {
            throw ConsentLedgerStorageError.revocationIntentVerificationFailed
        }
    }

    func clearAnalyticsRevocationIntentData() throws {
        userDefaults.removeObject(
            forKey: UserDefaultsKeys.analyticsRevocationIntent
        )
        guard userDefaults.data(
            forKey: UserDefaultsKeys.analyticsRevocationIntent
        ) == nil else {
            throw ConsentLedgerStorageError.revocationIntentVerificationFailed
        }
    }
}
