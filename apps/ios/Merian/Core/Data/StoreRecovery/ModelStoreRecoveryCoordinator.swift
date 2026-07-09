import CoreData
import CryptoKit
import Foundation

/// Handles launch-time SwiftData store recovery without touching account identity.
///
/// Store recovery is intentionally narrow. It may quarantine damaged local SwiftData
/// files, but it must never clear Keychain, Supabase auth sessions, device identity,
/// or cloud ownership state.
enum ModelStoreRecoveryCoordinator {
    enum StoreMigrationHint: Equatable, CustomStringConvertible {
        case currentStore
        case recentSource(Int)
        case fullHistorical

        var description: String {
            switch self {
            case .currentStore:
                return "current-store"
            case let .recentSource(version):
                return "recent-source-v\(version)"
            case .fullHistorical:
                return "full-historical"
            }
        }
    }

    struct StoreMigrationDecision: Equatable {
        let hasStoreArtifacts: Bool
        let storedSchemaMajorVersion: Int?
        let hint: StoreMigrationHint
    }

    private static let sqliteCorruptionCodes: Set<Int> = [11, 26] // SQLITE_CORRUPT, SQLITE_NOTADB
    private static let unknownModelVersionErrorCode = 134_504
    private static let manifestFilename = "recovery-manifest.json"
    private static let latestStartupDiagnosticKey = "app.merian.startup-store-diagnostic.latest"
    private static let storeModelVersionIdentifiersKey = "NSStoreModelVersionIdentifiers"
    private static let corruptionPhrases = [
        "database disk image is malformed",
        "file is not a database",
        "file is encrypted or is not a database",
        "sqlite_corrupt",
        "sqlite_notadb",
        "malformed database schema",
        "corrupt",
        "cannot use staged migration with an unknown model version",
        "unknown model version"
    ]
    private static let migrationFailurePhrases = [
        "migration",
        "migrate",
        "incompatible with the current model version",
        "incompatible version hash",
        "missing mapping model",
        "model version",
        "model reference",
        "current model reference",
        "next model reference",
        "the current model reference and the next model reference cannot be equal",
        "staged migration",
        "duplicate version checksums",
        "version checksum"
    ]

    static func defaultStoreURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static func makeStartupDiagnostic(
        storeURL: URL = defaultStoreURL(),
        currentSchemaMajor: Int,
        migrationSchemas: String,
        migrationStages: String,
        decision: StoreMigrationDecision,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> StartupStoreDiagnostic {
        StartupStoreDiagnostic(
            timestamp: ISO8601DateFormatter().string(from: now),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            currentSchemaMajor: currentSchemaMajor,
            migrationSchemas: migrationSchemas,
            migrationStages: migrationStages,
            selectedStrategy: decision.hint.description,
            store: storeDiagnosticSnapshot(at: storeURL, fileManager: fileManager)
        )
    }

    static func recordLatestStartupDiagnostic(_ diagnostic: StartupStoreDiagnostic) {
        guard let data = try? JSONEncoder.prettySorted.encode(diagnostic),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(text, forKey: latestStartupDiagnosticKey)
    }

    static func latestStartupDiagnosticText() -> String? {
        UserDefaults.standard.string(forKey: latestStartupDiagnosticKey)
    }

    static func startupDiagnosticText(_ diagnostic: StartupStoreDiagnostic) -> String? {
        guard let data = try? JSONEncoder.prettySorted.encode(diagnostic) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func diagnosticErrorSummaries(for error: Error) -> [StartupStoreDiagnosticError] {
        errorChain(from: error).map { candidate in
            let nsError = candidate as NSError
            return StartupStoreDiagnosticError(
                domain: nsError.domain,
                code: nsError.code,
                descriptionFingerprint: fingerprint(nsError.localizedDescription),
                failureReasonFingerprint: fingerprint(nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String),
                debugDescriptionFingerprint: fingerprint(nsError.userInfo[NSDebugDescriptionErrorKey] as? String)
            )
        }
    }

    static func migrationDecision(
        at storeURL: URL,
        fileManager: FileManager = .default,
        currentSchemaMajor: Int
    ) -> StoreMigrationDecision {
        let hasArtifacts = hasStoreArtifacts(at: storeURL, fileManager: fileManager)
        let storedSchemaMajor = hasArtifacts
            ? storedSchemaMajorVersion(at: storeURL, fileManager: fileManager)
            : nil

        return StoreMigrationDecision(
            hasStoreArtifacts: hasArtifacts,
            storedSchemaMajorVersion: storedSchemaMajor,
            hint: migrationHint(
                storedSchemaMajorVersion: storedSchemaMajor,
                hasStoreArtifacts: hasArtifacts,
                currentSchemaMajor: currentSchemaMajor
            )
        )
    }

    static func migrationHint(
        storedSchemaMajorVersion: Int?,
        hasStoreArtifacts: Bool,
        currentSchemaMajor: Int
    ) -> StoreMigrationHint {
        guard hasStoreArtifacts else { return .currentStore }
        guard let storedSchemaMajorVersion else { return .fullHistorical }

        if storedSchemaMajorVersion >= currentSchemaMajor {
            return .currentStore
        }

        if (42...48).contains(storedSchemaMajorVersion) {
            return .recentSource(storedSchemaMajorVersion)
        }

        return .fullHistorical
    }

    static func storedSchemaMajorVersion(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) -> Int? {
        guard hasStoreArtifacts(at: storeURL, fileManager: fileManager) else { return nil }

        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL,
                options: nil
            )
            return storedSchemaMajorVersion(from: metadata)
        } catch {
            MerianLog.general.error(
                "Unable to read SwiftData store metadata before launch migration selection: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    static func storedSchemaMajorVersion(from metadata: [String: Any]) -> Int? {
        schemaMajorVersions(from: metadata[storeModelVersionIdentifiersKey]).max()
    }

    private static func storeDiagnosticSnapshot(
        at storeURL: URL,
        fileManager: FileManager
    ) -> StartupStoreDiagnosticStore {
        let artifacts = storeArtifacts(for: storeURL, fileManager: fileManager)
        let artifactSummaries = artifacts.map { artifact in
            let attributes = try? fileManager.attributesOfItem(atPath: artifact.path)
            let size = attributes?[.size] as? NSNumber
            return StartupStoreDiagnosticArtifact(
                name: artifact.lastPathComponent,
                sizeBytes: size?.int64Value
            )
        }

        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL,
                options: nil
            )
            return StartupStoreDiagnosticStore(
                hasArtifacts: !artifactSummaries.isEmpty,
                artifacts: artifactSummaries,
                storedSchemaMajorVersion: storedSchemaMajorVersion(from: metadata),
                modelVersionIdentifiers: diagnosticStrings(from: metadata[storeModelVersionIdentifiersKey]),
                metadataFingerprints: diagnosticMetadataFingerprints(from: metadata),
                metadataReadError: nil
            )
        } catch {
            return StartupStoreDiagnosticStore(
                hasArtifacts: !artifactSummaries.isEmpty,
                artifacts: artifactSummaries,
                storedSchemaMajorVersion: nil,
                modelVersionIdentifiers: [],
                metadataFingerprints: [:],
                metadataReadError: diagnosticErrorSummaries(for: error).first
            )
        }
    }

    static func shouldAttemptRecovery(for error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let nsError = candidate as NSError
            if nsError.domain == NSSQLiteErrorDomain, sqliteCorruptionCodes.contains(nsError.code) {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadCorruptFileError {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == unknownModelVersionErrorCode {
                return true
            }

            let normalizedText = [
                nsError.localizedDescription,
                nsError.userInfo[NSDebugDescriptionErrorKey] as? String,
                nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")

            return corruptionPhrases.contains { normalizedText.contains($0) }
        }
    }

    static func shouldQuarantineStore(
        for error: Error,
        storeURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        shouldAttemptRecovery(for: error) && hasStoreArtifacts(at: storeURL, fileManager: fileManager)
    }

    static func safeModeFallback(for error: Error) -> ModelStoreSafeModeFallback {
        if isLikelyMigrationFailure(error) {
            return ModelStoreSafeModeFallback(
                message: "Merian started in safe mode because the local library could not finish upgrading. Your saved scans are still on disk, and local changes in this session are temporary until the app restarts with a healthy library.",
                telemetryReason: "persistent_store_migration_failed"
            )
        }

        return ModelStoreSafeModeFallback(
            message: "Merian started in safe mode after the persistent store failed to open. The app remains usable, but local changes in this session are temporary.",
            telemetryReason: "persistent_store_unavailable"
        )
    }

    static func isDuplicateVersionChecksumFailure(_ error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let nsError = candidate as NSError
            let normalizedText = [
                nsError.localizedDescription,
                nsError.userInfo[NSDebugDescriptionErrorKey] as? String,
                nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")

            return normalizedText.contains("duplicate version checksums") ||
                normalizedText.contains("version checksum") ||
                normalizedText.contains("the current model reference and the next model reference cannot be equal") ||
                normalizedText.contains("current model reference")
        }
    }

    static func hasStoreArtifacts(at storeURL: URL, fileManager: FileManager = .default) -> Bool {
        !storeArtifacts(for: storeURL, fileManager: fileManager).isEmpty
    }

    @discardableResult
    static func quarantineStoreArtifacts(
        at storeURL: URL,
        for error: Error? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL {
        let artifacts = storeArtifacts(for: storeURL, fileManager: fileManager)
        guard !artifacts.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let quarantineRoot = storeURL.deletingLastPathComponent().appending(path: "store-quarantine", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let quarantineDirectory = quarantineRoot.appending(path: "\(timestamp)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: false)

        for artifact in artifacts {
            let destination = quarantineDirectory.appending(path: artifact.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: artifact, to: destination)
        }

        writeManifest(
            to: quarantineDirectory,
            movedArtifacts: artifacts.map(\.lastPathComponent),
            error: error,
            now: now,
            fileManager: fileManager
        )

        return quarantineDirectory
    }

    private static func writeManifest(
        to quarantineDirectory: URL,
        movedArtifacts: [String],
        error: Error?,
        now: Date,
        fileManager: FileManager
    ) {
        let nsError = error.map { $0 as NSError }
        let manifest = ModelStoreRecoveryManifest(
            timestamp: ISO8601DateFormatter().string(from: now),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            reasonDomain: nsError?.domain,
            reasonCode: nsError?.code,
            reasonDescription: nsError?.localizedDescription,
            reasonFailureReason: nsError?.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
            movedArtifacts: movedArtifacts.sorted()
        )

        do {
            let data = try JSONEncoder.prettySorted.encode(manifest)
            let url = quarantineDirectory.appending(path: manifestFilename)
            fileManager.createFile(atPath: url.path, contents: data)
        } catch {
            MerianLog.general.error("Failed to write store recovery manifest: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func storeArtifacts(for storeURL: URL, fileManager: FileManager) -> [URL] {
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func schemaMajorVersions(from value: Any?) -> [Int] {
        guard let value else { return [] }

        switch value {
        case let number as NSNumber:
            return [number.intValue]
        case let string as String:
            return schemaMajorVersion(from: string).map { [$0] } ?? []
        case let strings as [String]:
            return strings.compactMap(schemaMajorVersion(from:))
        case let values as [Any]:
            return values.flatMap(schemaMajorVersions(from:))
        case let set as Set<String>:
            return set.compactMap(schemaMajorVersion(from:))
        case let set as NSSet:
            return set.allObjects.flatMap(schemaMajorVersions(from:))
        default:
            return []
        }
    }

    private static func schemaMajorVersion(from string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let directVersion = Int(trimmed) {
            return directVersion
        }

        let patterns = [
            #"(?i)(?:MerianSchemaV|SchemaV|Schema\.Version\(|Version\(|\bV)(\d+)"#,
            #"(?<!\d)(\d+)\.0\.0(?!\d)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let searchRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, options: [], range: searchRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: trimmed) else {
                continue
            }
            return Int(trimmed[range])
        }

        return nil
    }

    private static func diagnosticStrings(from value: Any?) -> [String] {
        guard let value else { return [] }

        switch value {
        case let string as String:
            return [diagnosticString(from: string)]
        case let number as NSNumber:
            return [number.stringValue]
        case let strings as [String]:
            return strings.map(diagnosticString(from:))
        case let values as [Any]:
            return values.flatMap(diagnosticStrings(from:))
        case let set as Set<String>:
            return set.map(diagnosticString(from:)).sorted()
        case let set as NSSet:
            return set.allObjects.flatMap(diagnosticStrings(from:)).sorted()
        default:
            return [fingerprint(String(describing: value)).map { "sha256:\($0)" } ?? "unavailable"]
        }
    }

    private static func diagnosticString(from string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }

        let privacySensitiveCharacters = CharacterSet(charactersIn: "/\\@")
        if trimmed.rangeOfCharacter(from: privacySensitiveCharacters) != nil || trimmed.count > 160 {
            return fingerprint(trimmed).map { "sha256:\($0)" } ?? "redacted"
        }

        return trimmed
    }

    private static func diagnosticMetadataFingerprints(from metadata: [String: Any]) -> [String: String] {
        metadata.reduce(into: [String: String]()) { result, element in
            let normalizedKey = element.key.lowercased()
            let shouldCapture = normalizedKey.contains("version") ||
                normalizedKey.contains("hash") ||
                normalizedKey.contains("checksum") ||
                normalizedKey.contains("model")
            guard shouldCapture else { return }

            let key = diagnosticString(from: element.key)
            let value = diagnosticStableDescription(from: element.value)
            result[key] = fingerprint(value).map { "sha256:\($0)" } ?? "unavailable"
        }
    }

    private static func diagnosticStableDescription(from value: Any?) -> String {
        guard let value else { return "nil" }

        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let data as Data:
            return "data:\(fingerprint(data))"
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let values as [Any]:
            return "[" + values.map(diagnosticStableDescription(from:)).joined(separator: ",") + "]"
        case let strings as [String]:
            return "[" + strings.sorted().joined(separator: ",") + "]"
        case let set as NSSet:
            return "[" + set.allObjects.map(diagnosticStableDescription(from:)).sorted().joined(separator: ",") + "]"
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().map { key in
                "\(key)=\(diagnosticStableDescription(from: dictionary[key]))"
            }.joined(separator: ";")
        default:
            return String(describing: value)
        }
    }

    private static func fingerprint(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return fingerprint(Data(text.utf8))
    }

    private static func fingerprint(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func errorChain(from rootError: Error) -> [Error] {
        var collected: [Error] = []
        var stack: [Error] = [rootError]

        while let next = stack.popLast() {
            collected.append(next)
            let nsError = next as NSError

            if let nestedError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                stack.append(nestedError)
            }
            if let nestedErrors = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                stack.append(contentsOf: nestedErrors)
            }
        }

        return collected
    }

    private static func isLikelyMigrationFailure(_ error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let nsError = candidate as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSPersistentStoreIncompatibleVersionHashError {
                return true
            }

            let normalizedText = [
                nsError.localizedDescription,
                nsError.userInfo[NSDebugDescriptionErrorKey] as? String,
                nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")

            return migrationFailurePhrases.contains { normalizedText.contains($0) }
        }
    }
}

struct ModelStoreSafeModeFallback: Equatable {
    let message: String
    let telemetryReason: String
}

struct StartupStoreDiagnostic: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let currentSchemaMajor: Int
    let migrationSchemas: String
    let migrationStages: String
    let selectedStrategy: String
    let store: StartupStoreDiagnosticStore
    private(set) var attempts: [StartupStoreDiagnosticAttempt]
    private(set) var finalOutcome: String?
    private(set) var finalReason: String?
    private(set) var quarantineAttempted: Bool
    private(set) var quarantinePerformed: Bool

    init(
        schemaVersion: Int = 1,
        timestamp: String,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        currentSchemaMajor: Int,
        migrationSchemas: String,
        migrationStages: String,
        selectedStrategy: String,
        store: StartupStoreDiagnosticStore,
        attempts: [StartupStoreDiagnosticAttempt] = [],
        finalOutcome: String? = nil,
        finalReason: String? = nil,
        quarantineAttempted: Bool = false,
        quarantinePerformed: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.currentSchemaMajor = currentSchemaMajor
        self.migrationSchemas = migrationSchemas
        self.migrationStages = migrationStages
        self.selectedStrategy = selectedStrategy
        self.store = store
        self.attempts = attempts
        self.finalOutcome = finalOutcome
        self.finalReason = finalReason
        self.quarantineAttempted = quarantineAttempted
        self.quarantinePerformed = quarantinePerformed
    }

    mutating func recordAttempt(name: String, outcome: String, error: Error? = nil) {
        attempts.append(
            StartupStoreDiagnosticAttempt(
                name: name,
                outcome: outcome,
                errorSummaries: error.map(ModelStoreRecoveryCoordinator.diagnosticErrorSummaries(for:)) ?? []
            )
        )
    }

    mutating func recordFinalOutcome(
        _ outcome: String,
        reason: String?,
        quarantineAttempted: Bool? = nil,
        quarantinePerformed: Bool? = nil
    ) {
        finalOutcome = outcome
        finalReason = reason
        if let quarantineAttempted {
            self.quarantineAttempted = quarantineAttempted
        }
        if let quarantinePerformed {
            self.quarantinePerformed = quarantinePerformed
        }
    }

    var telemetryProperties: [String: String] {
        var properties: [String: String] = [
            "diagnostic_schema": String(schemaVersion),
            "app_version": appVersion,
            "build_number": buildNumber,
            "current_schema_major": String(currentSchemaMajor),
            "migration_schemas": migrationSchemas,
            "migration_stages": migrationStages,
            "selected_strategy": selectedStrategy,
            "store_has_artifacts": String(store.hasArtifacts),
            "store_artifact_count": String(store.artifacts.count),
            "stored_schema_major": store.storedSchemaMajorVersion.map(String.init) ?? "none",
            "model_version_identifiers": limited(store.modelVersionIdentifiers.joined(separator: ",")),
            "attempt_count": String(attempts.count),
            "attempts": limited(attempts.map { "\($0.name):\($0.outcome)" }.joined(separator: ",")),
            "final_outcome": finalOutcome ?? "unknown",
            "final_reason": finalReason ?? "none",
            "quarantine_attempted": String(quarantineAttempted),
            "quarantine_performed": String(quarantinePerformed)
        ]

        if !store.artifacts.isEmpty {
            properties["store_artifacts"] = limited(
                store.artifacts
                    .map { "\($0.name):\($0.sizeBytes.map(String.init) ?? "unknown")" }
                    .joined(separator: ",")
            )
        }

        if !store.metadataFingerprints.isEmpty {
            properties["metadata_fingerprints"] = limited(
                store.metadataFingerprints
                    .keys
                    .sorted()
                    .map { "\($0)=\(store.metadataFingerprints[$0] ?? "")" }
                    .joined(separator: ",")
            )
        }

        if let metadataReadError = store.metadataReadError {
            properties["metadata_error"] = metadataReadError.telemetrySummary
        }

        if let firstError = attempts.lazy.flatMap(\.errorSummaries).first {
            properties["first_error"] = firstError.telemetrySummary
        }

        return properties
    }

    private func limited(_ value: String, maxLength: Int = 512) -> String {
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength))
    }
}

struct StartupStoreDiagnosticAttempt: Codable, Equatable {
    let name: String
    let outcome: String
    let errorSummaries: [StartupStoreDiagnosticError]
}

struct StartupStoreDiagnosticStore: Codable, Equatable {
    let hasArtifacts: Bool
    let artifacts: [StartupStoreDiagnosticArtifact]
    let storedSchemaMajorVersion: Int?
    let modelVersionIdentifiers: [String]
    let metadataFingerprints: [String: String]
    let metadataReadError: StartupStoreDiagnosticError?
}

struct StartupStoreDiagnosticArtifact: Codable, Equatable {
    let name: String
    let sizeBytes: Int64?
}

struct StartupStoreDiagnosticError: Codable, Equatable {
    let domain: String
    let code: Int
    let descriptionFingerprint: String?
    let failureReasonFingerprint: String?
    let debugDescriptionFingerprint: String?

    var telemetrySummary: String {
        [
            domain,
            String(code),
            descriptionFingerprint.map { "d:\($0)" },
            failureReasonFingerprint.map { "f:\($0)" },
            debugDescriptionFingerprint.map { "x:\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }
}

struct ModelStoreRecoveryManifest: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let reasonDomain: String?
    let reasonCode: Int?
    let reasonDescription: String?
    let reasonFailureReason: String?
    let movedArtifacts: [String]

    init(
        schemaVersion: Int = 1,
        timestamp: String,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        reasonDomain: String?,
        reasonCode: Int?,
        reasonDescription: String?,
        reasonFailureReason: String?,
        movedArtifacts: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.reasonDomain = reasonDomain
        self.reasonCode = reasonCode
        self.reasonDescription = reasonDescription
        self.reasonFailureReason = reasonFailureReason
        self.movedArtifacts = movedArtifacts
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
