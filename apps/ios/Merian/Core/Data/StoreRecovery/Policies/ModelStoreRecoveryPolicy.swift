import CoreData
import Foundation

extension ModelStoreRecoveryCoordinator {
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

        if let recentSource = RecentSourceSchema(rawValue: storedSchemaMajorVersion) {
            return .recentSource(recentSource)
        }

        return .fullHistorical
    }

    static func shouldAttemptRecovery(for error: Error) -> Bool {
        StoreRecoveryErrorPolicy.isCorruption(error)
    }

    static func shouldQuarantineStore(
        for error: Error,
        storeURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        shouldAttemptRecovery(for: error) && hasStoreArtifacts(at: storeURL, fileManager: fileManager)
    }

    static func shouldRescueStoreAfterMigrationFailure(
        for error: Error,
        decision: StoreMigrationDecision,
        storeURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard decision.hasStoreArtifacts,
              hasStoreArtifacts(at: storeURL, fileManager: fileManager),
              !shouldAttemptRecovery(for: error) else {
            return false
        }

        switch decision.hint {
        case .currentStore:
            return false
        case .recentSource, .fullHistorical:
            return true
        }
    }

    static func safeModeFallback(for error: Error) -> ModelStoreSafeModeFallback {
        if StoreRecoveryErrorPolicy.isLikelyMigrationFailure(error) {
            return ModelStoreSafeModeFallback(
                message: "Naturebook started in safe mode because the local library could not finish upgrading. Your saved scans are still on disk, and local changes in this session are temporary until the app restarts with a healthy library.",
                telemetryReason: "persistent_store_migration_failed"
            )
        }

        return ModelStoreSafeModeFallback(
            message: "Naturebook started in safe mode after the persistent store failed to open. The app remains usable, but local changes in this session are temporary.",
            telemetryReason: "persistent_store_unavailable"
        )
    }

    static func isDuplicateVersionChecksumFailure(_ error: Error) -> Bool {
        StoreRecoveryErrorPolicy.isDuplicateVersionChecksumFailure(error)
    }

    static func diagnosticErrorSummaries(
        for error: Error
    ) -> [StartupStoreDiagnosticError] {
        StoreRecoveryErrorPolicy.errorChain(from: error).map { candidate in
            let nsError = candidate as NSError
            return StartupStoreDiagnosticError(
                domain: StoreRecoveryPrivacyPolicy.sanitizedErrorDomain(
                    nsError.domain
                ),
                code: nsError.code,
                descriptionFingerprint: StoreRecoveryPrivacyPolicy.fingerprint(
                    nsError.localizedDescription
                ),
                failureReasonFingerprint: StoreRecoveryPrivacyPolicy.fingerprint(
                    nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
                ),
                debugDescriptionFingerprint: StoreRecoveryPrivacyPolicy.fingerprint(
                    nsError.userInfo[NSDebugDescriptionErrorKey] as? String
                )
            )
        }
    }
}

private enum StoreRecoveryErrorPolicy {
    private static let sqliteCorruptionCodes: Set<Int> = [
        11, // SQLITE_CORRUPT
        26 // SQLITE_NOTADB
    ]
    private static let unknownModelVersionErrorCode = 134_504
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

    static func isCorruption(_ error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let nsError = candidate as NSError
            if nsError.domain == NSSQLiteErrorDomain,
               sqliteCorruptionCodes.contains(nsError.code) {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileReadCorruptFileError {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == unknownModelVersionErrorCode {
                return true
            }

            return corruptionPhrases.contains { normalizedText(for: nsError).contains($0) }
        }
    }

    static func isDuplicateVersionChecksumFailure(_ error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let normalizedText = normalizedText(for: candidate as NSError)
            return normalizedText.contains("duplicate version checksums") ||
                normalizedText.contains("version checksum") ||
                normalizedText.contains("the current model reference and the next model reference cannot be equal") ||
                normalizedText.contains("current model reference")
        }
    }

    static func isLikelyMigrationFailure(_ error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let nsError = candidate as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSPersistentStoreIncompatibleVersionHashError {
                return true
            }

            let normalizedText = normalizedText(for: nsError)
            return migrationFailurePhrases.contains { normalizedText.contains($0) }
        }
    }

    static func errorChain(from rootError: Error) -> [Error] {
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

    private static func normalizedText(for error: NSError) -> String {
        [
            error.localizedDescription,
            error.userInfo[NSDebugDescriptionErrorKey] as? String,
            error.userInfo[NSLocalizedFailureReasonErrorKey] as? String
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")
    }
}
