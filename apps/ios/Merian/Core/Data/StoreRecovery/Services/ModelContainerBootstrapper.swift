import Foundation
import os
import SwiftData

enum ModelContainerBootstrapper {
    static func bootstrap() -> ModelContainerBootstrapOutcome {
        logBootstrapDiagnostics()
        let storeURL = ModelStoreRecoveryCoordinator.defaultStoreURL()
        let decision = ModelStoreRecoveryCoordinator.migrationDecision(
            at: storeURL,
            currentSchemaMajor: CurrentSchema.versionIdentifier.major
        )
        var diagnostic = ModelStoreRecoveryCoordinator.makeStartupDiagnostic(
            storeURL: storeURL,
            currentSchemaMajor: CurrentSchema.versionIdentifier.major,
            migrationSchemas:
                ModelContainerFactory.migrationSchemaVersionSummary(),
            migrationStages:
                ModelContainerFactory.migrationStageVersionSummary(),
            decision: decision
        )

        do {
            let container = try ModelContainerFactory
                .makePersistentContainerUsingStoreAwarePlan(
                    decision: decision,
                    diagnostic: &diagnostic
                )
            diagnostic.recordFinalOutcome("normal", reason: nil)
            ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(
                diagnostic
            )
            return ModelContainerBootstrapOutcome(
                container: container,
                startupStoreState: .normal,
                startupNotice: nil,
                telemetryEvent: nil
            )
        } catch {
            MerianLog.general.error(
                "CRITICAL: Failed to initialize ModelContainer. Error: \(error.localizedDescription)"
            )
            return recoverFromPersistentStoreFailure(
                error,
                decision: decision,
                storeURL: storeURL,
                diagnostic: diagnostic
            )
        }
    }

    static func fallbackInMemoryBootstrap(
        reason: String,
        telemetryReason: String = "persistent_store_unavailable",
        startupDiagnostic: StartupStoreDiagnostic? = nil,
        makeInMemoryContainer: () throws -> ModelContainer =
            ModelContainerFactory.makeInMemoryContainer
    ) -> ModelContainerBootstrapOutcome {
        var diagnostic = startupDiagnostic
        do {
            let container = try makeInMemoryContainer()
            diagnostic?.recordAttempt(
                name: "safe-mode-in-memory",
                outcome: "success"
            )
            diagnostic?.recordFinalOutcome(
                "safe_mode",
                reason: telemetryReason
            )
            record(diagnostic)
            return ModelContainerBootstrapOutcome(
                container: container,
                startupStoreState: .safeMode,
                startupNotice: StartupRecoveryNotice(
                    title: "Safe Mode Enabled",
                    message: reason,
                    diagnosticText: diagnostic.flatMap(
                        ModelStoreRecoveryCoordinator.startupDiagnosticText
                    )
                ),
                telemetryEvent: StartupRecoveryTelemetryEvent(
                    outcome: "safe_mode",
                    reason: telemetryReason,
                    properties: diagnostic?.telemetryProperties ?? [:]
                )
            )
        } catch {
            MerianLog.general.fault(
                "In-memory ModelContainer bootstrap failed: \(error.localizedDescription, privacy: .private)"
            )
            diagnostic?.recordAttempt(
                name: "safe-mode-in-memory",
                outcome: "failure",
                error: error
            )
            diagnostic?.recordFinalOutcome(
                "blocked",
                reason: "persistent_and_memory_store_unavailable"
            )
            record(diagnostic)
            return ModelContainerBootstrapOutcome(
                container: nil,
                startupStoreState: .safeMode,
                startupNotice: StartupRecoveryNotice(
                    title: "Startup Blocked",
                    message: "Naturebook could not open either the persistent library or the safe-mode in-memory store. Restart the app after freeing storage or reinstalling if the issue persists.",
                    diagnosticText: diagnostic.flatMap(
                        ModelStoreRecoveryCoordinator.startupDiagnosticText
                    )
                ),
                telemetryEvent: StartupRecoveryTelemetryEvent(
                    outcome: "blocked",
                    reason: "persistent_and_memory_store_unavailable",
                    properties: diagnostic?.telemetryProperties ?? [:]
                )
            )
        }
    }

    private static func recoverFromPersistentStoreFailure(
        _ error: Error,
        decision: ModelStoreRecoveryCoordinator.StoreMigrationDecision,
        storeURL: URL,
        diagnostic: StartupStoreDiagnostic
    ) -> ModelContainerBootstrapOutcome {
        var diagnostic = diagnostic
        if ModelStoreRecoveryCoordinator.shouldQuarantineStore(
            for: error,
            storeURL: storeURL
        ) {
            return recoverAfterQuarantine(
                error,
                storeURL: storeURL,
                diagnostic: &diagnostic
            )
        }

        if ModelStoreRecoveryCoordinator.shouldRescueStoreAfterMigrationFailure(
            for: error,
            decision: decision,
            storeURL: storeURL
        ) {
            return recoverAfterLegacyMigrationFailure(
                error,
                storeURL: storeURL,
                diagnostic: &diagnostic
            )
        }

        MerianLog.general.error(
            "ModelContainer recovery skipped because the failure did not match a verified corruption signature."
        )
        let safeModeFallback = ModelStoreRecoveryCoordinator.safeModeFallback(
            for: error
        )
        return fallbackInMemoryBootstrap(
            reason: safeModeFallback.message,
            telemetryReason: safeModeFallback.telemetryReason,
            startupDiagnostic: diagnostic
        )
    }

    private static func recoverAfterQuarantine(
        _ error: Error,
        storeURL: URL,
        diagnostic: inout StartupStoreDiagnostic
    ) -> ModelContainerBootstrapOutcome {
        do {
            let quarantineDirectory = try ModelStoreRecoveryCoordinator
                .quarantineStoreArtifacts(at: storeURL, for: error)
            let recoveredContainer = try ModelContainerFactory
                .makePersistentContainerWithoutMigrationPlan(
                    named: "post-quarantine-current-store",
                    diagnostic: &diagnostic
                )
            diagnostic.recordFinalOutcome(
                "recovered",
                reason: "corruption_quarantined",
                quarantineAttempted: true,
                quarantinePerformed: true
            )
            ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(
                diagnostic
            )
            MerianLog.general.error(
                "RECOVERY: Quarantined suspected-corrupt store artifacts to \(quarantineDirectory.lastPathComponent, privacy: .public) and recreated a fresh ModelContainer."
            )
            return ModelContainerBootstrapOutcome(
                container: recoveredContainer,
                startupStoreState: .recovered,
                startupNotice: StartupRecoveryNotice(
                    title: "Library Repaired",
                    message: "Naturebook recovered from a corrupted local store and rebuilt the library safely.",
                    diagnosticText: ModelStoreRecoveryCoordinator
                        .startupDiagnosticText(diagnostic)
                ),
                telemetryEvent: StartupRecoveryTelemetryEvent(
                    outcome: "recovered",
                    reason: "corruption_quarantined",
                    properties: diagnostic.telemetryProperties
                )
            )
        } catch let recoveryError {
            MerianLog.general.fault(
                "ModelContainer recovery failed after quarantine. Initial error: \(error.localizedDescription, privacy: .private) | Recovery error: \(recoveryError.localizedDescription, privacy: .private)"
            )
            diagnostic.recordAttempt(
                name: "post-quarantine-recovery",
                outcome: "failure",
                error: recoveryError
            )
            return fallbackInMemoryBootstrap(
                reason: "Naturebook started in safe mode because the local library could not be recovered. New work in this session is temporary until the app restarts with a healthy store.",
                telemetryReason: "persistent_store_recovery_failed",
                startupDiagnostic: diagnostic
            )
        }
    }

    private static func recoverAfterLegacyMigrationFailure(
        _ error: Error,
        storeURL: URL,
        diagnostic: inout StartupStoreDiagnostic
    ) -> ModelContainerBootstrapOutcome {
        var rescuePerformed = false
        do {
            let rescueDirectory = try ModelStoreRecoveryCoordinator
                .rescueStoreArtifactsAfterMigrationFailure(
                    at: storeURL,
                    for: error
                )
            rescuePerformed = true
            let recoveredContainer = try ModelContainerFactory
                .makePersistentContainerWithoutMigrationPlan(
                    named: "post-migration-rescue-current-store",
                    diagnostic: &diagnostic
                )
            diagnostic.recordFinalOutcome(
                "recovered",
                reason: "legacy_store_rescued",
                rescueAttempted: true,
                rescuePerformed: true
            )
            ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(
                diagnostic
            )
            MerianLog.general.error(
                "RECOVERY: Archived a legacy store that could not migrate to \(rescueDirectory.lastPathComponent, privacy: .public) and recreated a fresh ModelContainer."
            )
            return ModelContainerBootstrapOutcome(
                container: recoveredContainer,
                startupStoreState: .recovered,
                startupNotice: StartupRecoveryNotice(
                    title: "Library Rebuilt",
                    message: "Naturebook archived an older local library that could not be upgraded and started with a fresh library. Cloud sync can restore saved scans where available.",
                    diagnosticText: ModelStoreRecoveryCoordinator
                        .startupDiagnosticText(diagnostic)
                ),
                telemetryEvent: StartupRecoveryTelemetryEvent(
                    outcome: "recovered",
                    reason: "legacy_store_rescued",
                    properties: diagnostic.telemetryProperties
                )
            )
        } catch let rescueError {
            MerianLog.general.fault(
                "ModelContainer recovery failed after legacy migration rescue. Initial error: \(error.localizedDescription, privacy: .private) | Rescue error: \(rescueError.localizedDescription, privacy: .private)"
            )
            if !rescuePerformed {
                diagnostic.recordAttempt(
                    name: "migration-rescue-archive",
                    outcome: "failure",
                    error: rescueError
                )
            }
            diagnostic.recordFinalOutcome(
                "safe_mode",
                reason: "persistent_store_rescue_failed",
                rescueAttempted: true,
                rescuePerformed: rescuePerformed
            )
            return fallbackInMemoryBootstrap(
                reason: "Naturebook started in safe mode because an older local library could not be archived and rebuilt. New work in this session is temporary until the app restarts with a healthy store.",
                telemetryReason: "persistent_store_rescue_failed",
                startupDiagnostic: diagnostic
            )
        }
    }

    private static func record(_ diagnostic: StartupStoreDiagnostic?) {
        guard let diagnostic else { return }
        ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(diagnostic)
    }

    private static func logBootstrapDiagnostics() {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let buildNumber = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        let sourceRevision = Bundle.main.object(
            forInfoDictionaryKey: "MERIAN_SOURCE_REVISION"
        ) as? String ?? "unavailable"
        let sourceFingerprint = Bundle.main.object(
            forInfoDictionaryKey: "MERIAN_SOURCE_FINGERPRINT"
        ) as? String ?? "unavailable"
        let sourceState = Bundle.main.object(
            forInfoDictionaryKey: "MERIAN_SOURCE_STATE"
        ) as? String ?? "unavailable"
        let currentSchema = CurrentSchema.versionIdentifier.major
        let schemas = ModelContainerFactory.migrationSchemaVersionSummary()
        let stages = ModelContainerFactory.migrationStageVersionSummary()

        MerianLog.general.notice(
            "ModelContainer bootstrap diagnostics: app=\(appVersion, privacy: .public)(\(buildNumber, privacy: .public)) source=\(sourceRevision, privacy: .public) sourceFingerprint=\(sourceFingerprint, privacy: .public) sourceState=\(sourceState, privacy: .public) currentSchema=V\(currentSchema, privacy: .public) migrationSchemas=[\(schemas, privacy: .public)] migrationStages=[\(stages, privacy: .public)]"
        )
    }
}
