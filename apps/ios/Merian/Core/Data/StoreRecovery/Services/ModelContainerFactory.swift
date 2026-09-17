import Foundation
import os
import SwiftData

enum ModelContainerFactory {
    private static func makePersistentContainerUnchecked<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = persistentStoreConfiguration(for: schema)
        return try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: [config]
        )
    }

    private static func makePersistentContainerUncheckedWithoutMigrationPlan() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = persistentStoreConfiguration(for: schema)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func persistentStoreConfiguration(
        for schema: Schema
    ) -> ModelConfiguration {
        guard !TestExecutionCoordinator.isRunningTests else {
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        }
        return ModelStoreRecoveryCoordinator.productionStoreConfiguration(
            for: schema
        )
    }

    private static func makeInMemoryContainerUnchecked() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeContainerCatchingObjectiveCExceptions(
        _ buildContainer: @escaping () throws -> ModelContainer
    ) throws -> ModelContainer {
        var container: ModelContainer?
        var swiftError: Error?
        var exceptionError: NSError?

        _ = MerianCatchObjCException({
            do {
                container = try buildContainer()
            } catch {
                swiftError = error
            }
        }, &exceptionError)

        if let swiftError {
            throw swiftError
        }
        if let exceptionError {
            throw exceptionError
        }
        guard let container else {
            throw NSError(
                domain: "app.merian.model-container",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ModelContainer creation returned no container."
                ]
            )
        }
        return container
    }

    private static func makePersistentContainer<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type
    ) throws -> ModelContainer {
        try makeContainerCatchingObjectiveCExceptions {
            try makePersistentContainerUnchecked(migrationPlan: migrationPlan)
        }
    }

    private static func makePersistentContainerWithoutMigrationPlan() throws -> ModelContainer {
        try makeContainerCatchingObjectiveCExceptions {
            try makePersistentContainerUncheckedWithoutMigrationPlan()
        }
    }

    private static func recordPersistentContainerAttempt(
        named name: String,
        diagnostic: inout StartupStoreDiagnostic,
        _ buildContainer: () throws -> ModelContainer
    ) throws -> ModelContainer {
        do {
            let container = try buildContainer()
            diagnostic.recordAttempt(name: name, outcome: "success")
            return container
        } catch {
            diagnostic.recordAttempt(
                name: name,
                outcome: "failure",
                error: error
            )
            throw error
        }
    }

    private static func makePersistentContainer<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type,
        named name: String,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        try recordPersistentContainerAttempt(
            named: name,
            diagnostic: &diagnostic
        ) {
            try makePersistentContainer(migrationPlan: migrationPlan)
        }
    }

    static func makePersistentContainerWithoutMigrationPlan(
        named name: String,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        try recordPersistentContainerAttempt(
            named: name,
            diagnostic: &diagnostic
        ) {
            try makePersistentContainerWithoutMigrationPlan()
        }
    }

    private static func makePersistentContainerRetryingChecksumRepresentative(
        after error: Error,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        guard ModelStoreRecoveryCoordinator
            .isDuplicateVersionChecksumFailure(error) else {
            throw error
        }

        MerianLog.general.error(
            "ModelContainer migration plan hit duplicate version checksums; retrying with recent checksum-safe migration plans."
        )

        do {
            let recovered = try makePersistentContainerWithoutMigrationPlan(
                named: "checksum-current-store",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened without a migration plan; store was already current."
            )
            return recovered
        } catch let currentStoreError {
            MerianLog.general.error(
                "ModelContainer current-store retry failed: \(currentStoreError.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianReleasedActiveV50MigrationPlan.self,
                named: "checksum-recent-v50-released-active",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the released-active V50 checksum-safe migration plan."
            )
            return recovered
        } catch let releasedActiveV50Error {
            MerianLog.general.error(
                "ModelContainer released-active V50 checksum-safe retry failed: \(releasedActiveV50Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV50MigrationPlan.self,
                named: "checksum-recent-v50-frozen-snapshot",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the frozen-snapshot V50 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV50Error {
            MerianLog.general.error(
                "ModelContainer frozen-snapshot V50 checksum-safe retry failed: \(recentV50Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV49MigrationPlan.self,
                named: "checksum-recent-v49",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V49 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV49Error {
            MerianLog.general.error(
                "ModelContainer recent V49 checksum-safe retry failed: \(recentV49Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainerForV48Source(
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with a recent V48 startup recovery plan."
            )
            return recovered
        } catch let recentV48Error {
            MerianLog.general.error(
                "ModelContainer recent V48 startup recovery retry failed: \(recentV48Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV47MigrationPlan.self,
                named: "checksum-recent-v47",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V47 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV47Error {
            MerianLog.general.error(
                "ModelContainer recent V47 checksum-safe retry failed: \(recentV47Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV46MigrationPlan.self,
                named: "checksum-recent-v46",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V46 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV46Error {
            MerianLog.general.error(
                "ModelContainer recent V46 checksum-safe retry failed: \(recentV46Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV45MigrationPlan.self,
                named: "checksum-recent-v45",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V45 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV45Error {
            MerianLog.general.error(
                "ModelContainer recent V45 checksum-safe retry failed: \(recentV45Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV44MigrationPlan.self,
                named: "checksum-recent-v44",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V44 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV44Error {
            MerianLog.general.error(
                "ModelContainer recent V44 checksum-safe retry failed: \(recentV44Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV43MigrationPlan.self,
                named: "checksum-recent-v43",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V43 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV43Error {
            MerianLog.general.error(
                "ModelContainer recent V43 checksum-safe retry failed: \(recentV43Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV42MigrationPlan.self,
                named: "checksum-recent-v42",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V42 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV42Error {
            MerianLog.general.error(
                "ModelContainer recent V42 checksum-safe retry failed. Primary error: \(error.localizedDescription, privacy: .private) | Retry error: \(recentV42Error.localizedDescription, privacy: .private)"
            )
            throw error
        }
    }

    private static func makePersistentContainerForV48Source(
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        do {
            return try makePersistentContainer(
                migrationPlan: MerianRecentV48MigrationPlan.self,
                named: "recent-v48-known-good",
                diagnostic: &diagnostic
            )
        } catch let knownGoodV48Error {
            MerianLog.general.error(
                "ModelContainer known-good V48 startup recovery failed: \(knownGoodV48Error.localizedDescription, privacy: .private)"
            )
        }

        return try makePersistentContainer(
            migrationPlan: MerianOptionalQueueV48RecoveryPlan.self,
            named: "recent-v48-optional-queue",
            diagnostic: &diagnostic
        )
    }

    private static func makePersistentContainerForRecentSource(
        _ source: ModelStoreRecoveryCoordinator.RecentSourceSchema,
        v50StoreVariant: ModelStoreRecoveryCoordinator.V50StoreVariant?,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        switch source {
        case .v50:
            switch v50StoreVariant {
            case .releasedActive:
                return try makePersistentContainer(
                    migrationPlan: MerianReleasedActiveV50MigrationPlan.self,
                    named: "recent-v50-released-active",
                    diagnostic: &diagnostic
                )
            case .frozenSnapshot, nil:
                return try makePersistentContainer(
                    migrationPlan: MerianRecentV50MigrationPlan.self,
                    named: "recent-v50-frozen-snapshot",
                    diagnostic: &diagnostic
                )
            case .unknown:
                throw NSError(
                    domain: "app.merian.model-container",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The V50 store model signature is not an allowlisted released graph."
                    ]
                )
            }
        case .v49:
            return try makePersistentContainer(
                migrationPlan: MerianRecentV49MigrationPlan.self,
                named: "recent-v49",
                diagnostic: &diagnostic
            )
        case .v48:
            return try makePersistentContainerForV48Source(
                diagnostic: &diagnostic
            )
        case .v47:
            return try makePersistentContainer(
                migrationPlan: MerianRecentV47MigrationPlan.self,
                named: "recent-v47",
                diagnostic: &diagnostic
            )
        case .v46:
            return try makePersistentContainer(
                migrationPlan: MerianRecentV46MigrationPlan.self,
                named: "recent-v46",
                diagnostic: &diagnostic
            )
        case .v45:
            return try makePersistentContainer(
                migrationPlan: MerianRecentV45MigrationPlan.self,
                named: "recent-v45",
                diagnostic: &diagnostic
            )
        case .v44:
            return try makePersistentContainer(
                migrationPlan: MerianRecentV44MigrationPlan.self,
                named: "recent-v44",
                diagnostic: &diagnostic
            )
        case .v43:
            return try makePersistentContainer(
                migrationPlan: MerianRecentV43MigrationPlan.self,
                named: "recent-v43",
                diagnostic: &diagnostic
            )
        case .v42:
            return try makePersistentContainer(
                migrationPlan: MerianRecentV42MigrationPlan.self,
                named: "recent-v42",
                diagnostic: &diagnostic
            )
        }
    }

    private static func makePersistentContainer(
        forStoreMigrationHint hint: ModelStoreRecoveryCoordinator.StoreMigrationHint,
        v50StoreVariant: ModelStoreRecoveryCoordinator.V50StoreVariant?,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        switch hint {
        case .currentStore:
            return try makePersistentContainerWithoutMigrationPlan(
                named: "current-store",
                diagnostic: &diagnostic
            )
        case let .recentSource(source):
            return try makePersistentContainerForRecentSource(
                source,
                v50StoreVariant: v50StoreVariant,
                diagnostic: &diagnostic
            )
        case .fullHistorical:
            return try makePersistentContainer(
                migrationPlan: MerianMigrationPlan.self,
                named: "full-historical",
                diagnostic: &diagnostic
            )
        }
    }

    static func makePersistentContainerUsingStoreAwarePlan(
        decision: ModelStoreRecoveryCoordinator.StoreMigrationDecision,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        let detectedSchema = decision.storedSchemaMajorVersion
            .map { "V\($0)" } ?? "unavailable"

        MerianLog.general.notice(
            "ModelContainer store-aware migration selection: hasStoreArtifacts=\(decision.hasStoreArtifacts, privacy: .public) storedSchema=\(detectedSchema, privacy: .public) strategy=\(decision.strategyDescription, privacy: .public)"
        )

        do {
            return try makePersistentContainer(
                forStoreMigrationHint: decision.hint,
                v50StoreVariant: decision.v50StoreVariant,
                diagnostic: &diagnostic
            )
        } catch {
            return try makePersistentContainerRetryingChecksumRepresentative(
                after: error,
                diagnostic: &diagnostic
            )
        }
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainerCatchingObjectiveCExceptions {
            try makeInMemoryContainerUnchecked()
        }
    }

    static func migrationSchemaVersionSummary() -> String {
        MerianMigrationPlan.schemas
            .map { "\($0.versionIdentifier.major)" }
            .joined(separator: ",")
    }

    static func migrationStageVersionSummary() -> String {
        MerianMigrationPlan.stages
            .map { stage -> String in
                switch stage {
                case let .lightweight(fromVersion, toVersion):
                    return "\(fromVersion.versionIdentifier.major)>\(toVersion.versionIdentifier.major):L"
                case let .custom(fromVersion, toVersion, _, _):
                    return "\(fromVersion.versionIdentifier.major)>\(toVersion.versionIdentifier.major):C"
                @unknown default:
                    return "unknown"
                }
            }
            .joined(separator: ",")
    }
}
