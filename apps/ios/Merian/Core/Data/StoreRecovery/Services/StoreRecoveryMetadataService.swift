import CoreData
import Foundation

extension ModelStoreRecoveryCoordinator {
    static func makeStartupDiagnostic(
        storeURL: URL = defaultStoreURL(),
        currentSchemaMajor: Int,
        migrationSchemas: String,
        migrationStages: String,
        decision: StoreMigrationDecision,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> StartupStoreDiagnostic {
        StoreRecoveryMetadataService.makeStartupDiagnostic(
            storeURL: storeURL,
            currentSchemaMajor: currentSchemaMajor,
            migrationSchemas: migrationSchemas,
            migrationStages: migrationStages,
            decision: decision,
            fileManager: fileManager,
            now: now
        )
    }

    static func recordLatestStartupDiagnostic(_ diagnostic: StartupStoreDiagnostic) {
        StoreRecoveryMetadataService.recordLatestStartupDiagnostic(diagnostic)
    }

    static func latestStartupDiagnosticText() -> String? {
        StoreRecoveryMetadataService.latestStartupDiagnosticText()
    }

    static func startupDiagnosticText(_ diagnostic: StartupStoreDiagnostic) -> String? {
        StoreRecoveryMetadataService.startupDiagnosticText(diagnostic)
    }

    static func migrationDecision(
        at storeURL: URL,
        fileManager: FileManager = .default,
        currentSchemaMajor: Int
    ) -> StoreMigrationDecision {
        StoreRecoveryMetadataService.migrationDecision(
            at: storeURL,
            fileManager: fileManager,
            currentSchemaMajor: currentSchemaMajor
        )
    }

    static func storedSchemaMajorVersion(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) -> Int? {
        StoreRecoveryMetadataService.storedSchemaMajorVersion(
            at: storeURL,
            fileManager: fileManager
        )
    }

    static func storedSchemaMajorVersion(from metadata: [String: Any]) -> Int? {
        StoreRecoveryMetadataService.storedSchemaMajorVersion(from: metadata)
    }

    static func v50StoreVariant(from metadata: [String: Any]) -> V50StoreVariant? {
        StoreRecoveryMetadataService.v50StoreVariant(from: metadata)
    }
}

private enum StoreRecoveryMetadataService {
    private static let latestStartupDiagnosticKey =
        "app.merian.startup-store-diagnostic.latest"
    private static let storeModelVersionIdentifiersKey =
        "NSStoreModelVersionIdentifiers"
    private static let storeModelVersionChecksumKey =
        "NSStoreModelVersionChecksumKey"

    /// SHA-256 prefixes of Core Data's stable model-checksum strings. These are
    /// privacy-safe signatures, verified against both reconstructed disk stores
    /// and the processed-release diagnostic from build 327.
    private static let frozenSnapshotV50ChecksumFingerprint =
        "b9fa43ac9095301ecdce20e5"
    private static let releasedActiveV50ChecksumFingerprint =
        "9a0841f675241b21f5ad5c10"

    static func makeStartupDiagnostic(
        storeURL: URL,
        currentSchemaMajor: Int,
        migrationSchemas: String,
        migrationStages: String,
        decision: ModelStoreRecoveryCoordinator.StoreMigrationDecision,
        fileManager: FileManager,
        now: Date
    ) -> StartupStoreDiagnostic {
        StartupStoreDiagnostic(
            timestamp: ISO8601DateFormatter().string(from: now),
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            buildNumber: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            currentSchemaMajor: currentSchemaMajor,
            migrationSchemas: migrationSchemas,
            migrationStages: migrationStages,
            selectedStrategy: decision.strategyDescription,
            store: storeDiagnosticSnapshot(
                at: storeURL,
                fileManager: fileManager
            )
        )
    }

    static func recordLatestStartupDiagnostic(_ diagnostic: StartupStoreDiagnostic) {
        guard let data = try? StoreRecoveryJSONCoding.encode(diagnostic),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(text, forKey: latestStartupDiagnosticKey)
    }

    static func latestStartupDiagnosticText() -> String? {
        UserDefaults.standard.string(forKey: latestStartupDiagnosticKey)
    }

    static func startupDiagnosticText(_ diagnostic: StartupStoreDiagnostic) -> String? {
        guard let data = try? StoreRecoveryJSONCoding.encode(diagnostic) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func migrationDecision(
        at storeURL: URL,
        fileManager: FileManager,
        currentSchemaMajor: Int
    ) -> ModelStoreRecoveryCoordinator.StoreMigrationDecision {
        let hasArtifacts = !StoreRecoveryArtifactArchiver.artifacts(
            for: storeURL,
            fileManager: fileManager
        ).isEmpty
        var metadata: [String: Any]?
        if hasArtifacts {
            do {
                metadata = try persistentStoreMetadata(at: storeURL)
            } catch {
                MerianLog.general.error(
                    "Unable to read SwiftData store metadata before launch migration selection: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        let storedSchemaMajor = metadata.flatMap(storedSchemaMajorVersion(from:))

        return ModelStoreRecoveryCoordinator.StoreMigrationDecision(
            hasStoreArtifacts: hasArtifacts,
            storedSchemaMajorVersion: storedSchemaMajor,
            hint: ModelStoreRecoveryCoordinator.migrationHint(
                storedSchemaMajorVersion: storedSchemaMajor,
                hasStoreArtifacts: hasArtifacts,
                currentSchemaMajor: currentSchemaMajor
            ),
            v50StoreVariant: metadata.flatMap(v50StoreVariant(from:))
        )
    }

    static func storedSchemaMajorVersion(
        at storeURL: URL,
        fileManager: FileManager
    ) -> Int? {
        guard !StoreRecoveryArtifactArchiver.artifacts(
            for: storeURL,
            fileManager: fileManager
        ).isEmpty else {
            return nil
        }

        do {
            return storedSchemaMajorVersion(
                from: try persistentStoreMetadata(at: storeURL)
            )
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

    static func v50StoreVariant(
        from metadata: [String: Any]
    ) -> ModelStoreRecoveryCoordinator.V50StoreVariant? {
        guard storedSchemaMajorVersion(from: metadata) == 50 else { return nil }
        guard let checksum = metadata[storeModelVersionChecksumKey] else {
            return .unknown
        }

        let description = StoreRecoveryPrivacyPolicy.stableDescription(
            from: checksum
        )
        guard let checksumFingerprint = StoreRecoveryPrivacyPolicy.fingerprint(
            description
        ) else {
            return .unknown
        }

        switch checksumFingerprint {
        case frozenSnapshotV50ChecksumFingerprint:
            return .frozenSnapshot
        case releasedActiveV50ChecksumFingerprint:
            return .releasedActive
        default:
            return .unknown
        }
    }

    private static func storeDiagnosticSnapshot(
        at storeURL: URL,
        fileManager: FileManager
    ) -> StartupStoreDiagnosticStore {
        let artifacts = StoreRecoveryArtifactArchiver.artifacts(
            for: storeURL,
            fileManager: fileManager
        )
        let artifactSummaries = artifacts.map { artifact in
            let attributes = try? fileManager.attributesOfItem(
                atPath: artifact.path
            )
            let size = attributes?[.size] as? NSNumber
            return StartupStoreDiagnosticArtifact(
                name: artifact.lastPathComponent,
                sizeBytes: size?.int64Value
            )
        }

        guard !artifactSummaries.isEmpty else {
            return StartupStoreDiagnosticStore(
                hasArtifacts: false,
                artifacts: [],
                storedSchemaMajorVersion: nil,
                modelVersionIdentifiers: [],
                metadataFingerprints: [:],
                metadataReadError: nil
            )
        }

        do {
            let metadata = try persistentStoreMetadata(at: storeURL)
            return StartupStoreDiagnosticStore(
                hasArtifacts: true,
                artifacts: artifactSummaries,
                storedSchemaMajorVersion: storedSchemaMajorVersion(
                    from: metadata
                ),
                modelVersionIdentifiers: diagnosticStrings(
                    from: metadata[storeModelVersionIdentifiersKey]
                ),
                metadataFingerprints: diagnosticMetadataFingerprints(
                    from: metadata
                ),
                metadataReadError: nil
            )
        } catch {
            return StartupStoreDiagnosticStore(
                hasArtifacts: true,
                artifacts: artifactSummaries,
                storedSchemaMajorVersion: nil,
                modelVersionIdentifiers: [],
                metadataFingerprints: [:],
                metadataReadError: ModelStoreRecoveryCoordinator
                    .diagnosticErrorSummaries(for: error).first
            )
        }
    }

    private static func persistentStoreMetadata(
        at storeURL: URL
    ) throws -> [String: Any] {
        try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
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
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let searchRange = NSRange(
                trimmed.startIndex..<trimmed.endIndex,
                in: trimmed
            )
            guard let match = regex.firstMatch(
                in: trimmed,
                options: [],
                range: searchRange
            ),
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
            return [
                StoreRecoveryPrivacyPolicy.sanitizedMetadataString(string)
            ]
        case let number as NSNumber:
            return [number.stringValue]
        case let strings as [String]:
            return strings.map(
                StoreRecoveryPrivacyPolicy.sanitizedMetadataString
            )
        case let values as [Any]:
            return values.flatMap(diagnosticStrings(from:))
        case let set as Set<String>:
            return set.map(
                StoreRecoveryPrivacyPolicy.sanitizedMetadataString
            )
                .sorted()
        case let set as NSSet:
            return set.allObjects.flatMap(diagnosticStrings(from:)).sorted()
        default:
            let description = String(describing: value)
            return [
                StoreRecoveryPrivacyPolicy.fingerprint(description)
                    .map { "sha256:\($0)" } ?? "unavailable"
            ]
        }
    }

    private static func diagnosticMetadataFingerprints(
        from metadata: [String: Any]
    ) -> [String: String] {
        metadata.reduce(into: [String: String]()) { result, element in
            let normalizedKey = element.key.lowercased()
            let shouldCapture = normalizedKey.contains("version") ||
                normalizedKey.contains("hash") ||
                normalizedKey.contains("checksum") ||
                normalizedKey.contains("model")
            guard shouldCapture else { return }

            let key = StoreRecoveryPrivacyPolicy.sanitizedMetadataString(
                element.key
            )
            let value = StoreRecoveryPrivacyPolicy.stableDescription(
                from: element.value
            )
            result[key] = StoreRecoveryPrivacyPolicy.fingerprint(value)
                .map { "sha256:\($0)" } ?? "unavailable"
        }
    }
}
