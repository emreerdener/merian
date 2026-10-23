import Foundation
import os
import SwiftData

extension ModelContainerFactory {
    @MainActor
    struct Persistent {
        let session: PersistentStoreBootstrapSession

        struct Opened {
            enum Disposition { case firstSuccess, retried }
            let container: ModelContainer
            let disposition: Disposition
        }

        private func optionalRecovery(_ body: () throws -> ModelContainer) throws -> ModelContainer? {
            do { return try body() }
            catch {
                try session.requireRecoverable(error)
                return nil
            }
        }

        private func makePersistentContainerUnchecked<MigrationPlan: SchemaMigrationPlan>(
            migrationPlan: MigrationPlan.Type
        ) throws -> ModelContainer {
            let schema = session.schema
            let config = session.configuration
            return try ModelContainer(for: schema, migrationPlan: migrationPlan, configurations: [config])
        }

        private func makePersistentContainerUncheckedWithoutMigrationPlan() throws -> ModelContainer {
            let schema = session.schema
            let config = session.configuration
            return try ModelContainer(for: schema, configurations: [config])
        }

        private func makePersistentContainer<MigrationPlan: SchemaMigrationPlan>(
            migrationPlan: MigrationPlan.Type
        ) throws -> ModelContainer {
            try session.construct {
                try ModelContainerFactory.makeContainerCatchingObjectiveCExceptions {
                    try self.makePersistentContainerUnchecked(migrationPlan: migrationPlan)
                }
            }
        }

        private func makePersistentContainerWithoutMigrationPlan() throws -> ModelContainer {
            try session.construct {
                try ModelContainerFactory.makeContainerCatchingObjectiveCExceptions {
                    try self.makePersistentContainerUncheckedWithoutMigrationPlan()
                }
            }
        }

        private func recordPersistentContainerAttempt(
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
                try session.requireRecoverable(error)
                throw error
            }
        }

        private func makePersistentContainer<MigrationPlan: SchemaMigrationPlan>(
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

        func makePersistentContainerWithoutMigrationPlan(
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

        private func makePersistentContainerRetryingChecksumRepresentative(
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
                try session.requireRecoverable(currentStoreError)
                MerianLog.general.error(
                    "ModelContainer current-store retry failed: \(currentStoreError.localizedDescription, privacy: .private)"
                )
            }

            // The named helper records each failure in the startup diagnostic.
            // A failed recent source advances to the next exact representative.
            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV65MigrationPlan.self, named: "checksum-recent-v65", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV64MigrationPlan.self, named: "checksum-recent-v64", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV63MigrationPlan.self, named: "checksum-recent-v63", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV62MigrationPlan.self, named: "checksum-recent-v62", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV61MigrationPlan.self, named: "checksum-recent-v61", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV60MigrationPlan.self, named: "checksum-recent-v60", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV59MigrationPlan.self, named: "checksum-recent-v59", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV58MigrationPlan.self, named: "checksum-recent-v58", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV57MigrationPlan.self, named: "checksum-recent-v57", diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV56MigrationPlan.self,
                named: "checksum-recent-v56",
                diagnostic: &diagnostic
            ) }) { return recovered }

            if let recovered = try optionalRecovery({ try makePersistentContainer(
                migrationPlan: MerianRecentV55MigrationPlan.self,
                named: "checksum-recent-v55",
                diagnostic: &diagnostic
            ) }) { return recovered }

            do {
                return try makePersistentContainer(
                    migrationPlan: MerianRecentV54MigrationPlan.self,
                    named: "checksum-recent-v54",
                    diagnostic: &diagnostic
                )
            } catch let recentV54Error {
                try session.requireRecoverable(recentV54Error)
                MerianLog.general.error(
                    "ModelContainer V54 checksum-safe retry failed: \(recentV54Error.localizedDescription, privacy: .private)"
                )
            }

            do {
                return try makePersistentContainer(
                    migrationPlan: MerianRecentV53MigrationPlan.self,
                    named: "checksum-recent-v53",
                    diagnostic: &diagnostic
                )
            } catch let recentV53Error {
                try session.requireRecoverable(recentV53Error)
                MerianLog.general.error(
                    "ModelContainer V53 checksum-safe retry failed: \(recentV53Error.localizedDescription, privacy: .private)"
                )
            }

            do {
                return try makePersistentContainer(
                    migrationPlan: MerianRecentV52MigrationPlan.self,
                    named: "checksum-recent-v52",
                    diagnostic: &diagnostic
                )
            } catch let recentV52Error {
                try session.requireRecoverable(recentV52Error)
                MerianLog.general.error(
                    "ModelContainer V52 checksum-safe retry failed: \(recentV52Error.localizedDescription, privacy: .private)"
                )
            }

            do {
                return try makePersistentContainer(
                    migrationPlan: MerianRecentV51MigrationPlan.self,
                    named: "checksum-recent-v51",
                    diagnostic: &diagnostic
                )
            } catch let recentV51Error {
                try session.requireRecoverable(recentV51Error)
                MerianLog.general.error(
                    "ModelContainer V51 checksum-safe retry failed: \(recentV51Error.localizedDescription, privacy: .private)"
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
                try session.requireRecoverable(releasedActiveV50Error)
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
                try session.requireRecoverable(recentV50Error)
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
                try session.requireRecoverable(recentV49Error)
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
                try session.requireRecoverable(recentV48Error)
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
                try session.requireRecoverable(recentV47Error)
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
                try session.requireRecoverable(recentV46Error)
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
                try session.requireRecoverable(recentV45Error)
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
                try session.requireRecoverable(recentV44Error)
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
                try session.requireRecoverable(recentV43Error)
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
                try session.requireRecoverable(recentV42Error)
                MerianLog.general.error(
                    "ModelContainer recent V42 checksum-safe retry failed. Primary error: \(error.localizedDescription, privacy: .private) | Retry error: \(recentV42Error.localizedDescription, privacy: .private)"
                )
                throw error
            }
        }

        private func makePersistentContainerForV48Source(
            diagnostic: inout StartupStoreDiagnostic
        ) throws -> ModelContainer {
            do {
                return try makePersistentContainer(
                    migrationPlan: MerianRecentV48MigrationPlan.self,
                    named: "recent-v48-known-good",
                    diagnostic: &diagnostic
                )
            } catch let knownGoodV48Error {
                try session.requireRecoverable(knownGoodV48Error)
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

        private func makePersistentContainerForRecentSource(
            _ source: ModelStoreRecoveryCoordinator.RecentSourceSchema,
            v50StoreVariant: ModelStoreRecoveryCoordinator.V50StoreVariant?,
            diagnostic: inout StartupStoreDiagnostic
        ) throws -> ModelContainer {
            switch source {
            case .v65:
                return try makePersistentContainer(migrationPlan: MerianRecentV65MigrationPlan.self, named: "recent-v65", diagnostic: &diagnostic)
            case .v64:
                return try makePersistentContainer(migrationPlan: MerianRecentV64MigrationPlan.self, named: "recent-v64", diagnostic: &diagnostic)
            case .v63:
                return try makePersistentContainer(migrationPlan: MerianRecentV63MigrationPlan.self, named: "recent-v63", diagnostic: &diagnostic)
            case .v62:
                return try makePersistentContainer(migrationPlan: MerianRecentV62MigrationPlan.self, named: "recent-v62", diagnostic: &diagnostic)
            case .v61:
                return try makePersistentContainer(migrationPlan: MerianRecentV61MigrationPlan.self, named: "recent-v61", diagnostic: &diagnostic)
            case .v60:
                return try makePersistentContainer(migrationPlan: MerianRecentV60MigrationPlan.self, named: "recent-v60", diagnostic: &diagnostic)
            case .v59:
                return try makePersistentContainer(migrationPlan: MerianRecentV59MigrationPlan.self, named: "recent-v59", diagnostic: &diagnostic)
            case .v58:
                return try makePersistentContainer(migrationPlan: MerianRecentV58MigrationPlan.self, named: "recent-v58", diagnostic: &diagnostic)
            case .v57:
                return try makePersistentContainer(migrationPlan: MerianRecentV57MigrationPlan.self, named: "recent-v57", diagnostic: &diagnostic)
            case .v56:
                return try makePersistentContainer(migrationPlan: MerianRecentV56MigrationPlan.self, named: "recent-v56", diagnostic: &diagnostic)
            case .v55:
                return try makePersistentContainer(migrationPlan: MerianRecentV55MigrationPlan.self, named: "recent-v55", diagnostic: &diagnostic)
            case .v54:
                return try makePersistentContainer(migrationPlan: MerianRecentV54MigrationPlan.self, named: "recent-v54", diagnostic: &diagnostic)
            case .v53:
                return try makePersistentContainer(migrationPlan: MerianRecentV53MigrationPlan.self, named: "recent-v53", diagnostic: &diagnostic)
            case .v52:
                return try makePersistentContainer(migrationPlan: MerianRecentV52MigrationPlan.self, named: "recent-v52", diagnostic: &diagnostic)
            case .v51:
                return try makePersistentContainer(migrationPlan: MerianRecentV51MigrationPlan.self, named: "recent-v51", diagnostic: &diagnostic)
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
                return try makePersistentContainer(migrationPlan: MerianRecentV49MigrationPlan.self, named: "recent-v49", diagnostic: &diagnostic)
            case .v48:
                return try makePersistentContainerForV48Source(
                    diagnostic: &diagnostic
                )
            case .v47:
                return try makePersistentContainer(migrationPlan: MerianRecentV47MigrationPlan.self, named: "recent-v47", diagnostic: &diagnostic)
            case .v46:
                return try makePersistentContainer(migrationPlan: MerianRecentV46MigrationPlan.self, named: "recent-v46", diagnostic: &diagnostic)
            case .v45:
                return try makePersistentContainer(migrationPlan: MerianRecentV45MigrationPlan.self, named: "recent-v45", diagnostic: &diagnostic)
            case .v44:
                return try makePersistentContainer(migrationPlan: MerianRecentV44MigrationPlan.self, named: "recent-v44", diagnostic: &diagnostic)
            case .v43:
                return try makePersistentContainer(migrationPlan: MerianRecentV43MigrationPlan.self, named: "recent-v43", diagnostic: &diagnostic)
            case .v42:
                return try makePersistentContainer(migrationPlan: MerianRecentV42MigrationPlan.self, named: "recent-v42", diagnostic: &diagnostic)
            }
        }

        private func makePersistentContainer(
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

        func makePersistentContainerUsingStoreAwarePlan(
            decision: ModelStoreRecoveryCoordinator.StoreMigrationDecision,
            diagnostic: inout StartupStoreDiagnostic
        ) throws -> Opened {
            let detectedSchema = decision.storedSchemaMajorVersion
                .map { "V\($0)" } ?? "unavailable"

            MerianLog.general.notice(
                "ModelContainer store-aware migration selection: hasStoreArtifacts=\(decision.hasStoreArtifacts, privacy: .public) storedSchema=\(detectedSchema, privacy: .public) strategy=\(decision.strategyDescription, privacy: .public)"
            )

            do {
                let container = try makePersistentContainer(
                    forStoreMigrationHint: decision.hint,
                    v50StoreVariant: decision.v50StoreVariant,
                    diagnostic: &diagnostic
                )
                return Opened(container: container, disposition: session.attempts == 1 ? .firstSuccess : .retried)
            } catch {
                try session.requireRecoverable(error)
                let container = try makePersistentContainerRetryingChecksumRepresentative(
                    after: error,
                    diagnostic: &diagnostic
                )
                return Opened(container: container, disposition: .retried)
            }
        }
    }
}
