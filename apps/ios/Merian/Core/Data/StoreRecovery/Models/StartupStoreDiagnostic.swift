import Foundation

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
    private(set) var rescueAttempted: Bool
    private(set) var rescuePerformed: Bool

    init(
        schemaVersion: Int = 2,
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
        quarantinePerformed: Bool = false,
        rescueAttempted: Bool = false,
        rescuePerformed: Bool = false
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
        self.rescueAttempted = rescueAttempted
        self.rescuePerformed = rescuePerformed
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
        quarantinePerformed: Bool? = nil,
        rescueAttempted: Bool? = nil,
        rescuePerformed: Bool? = nil
    ) {
        finalOutcome = outcome
        finalReason = reason
        if let quarantineAttempted {
            self.quarantineAttempted = quarantineAttempted
        }
        if let quarantinePerformed {
            self.quarantinePerformed = quarantinePerformed
        }
        if let rescueAttempted {
            self.rescueAttempted = rescueAttempted
        }
        if let rescuePerformed {
            self.rescuePerformed = rescuePerformed
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
            "quarantine_performed": String(quarantinePerformed),
            "rescue_attempted": String(rescueAttempted),
            "rescue_performed": String(rescuePerformed)
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
