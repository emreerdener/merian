import Foundation
import os
import SwiftData

enum ModelContainerFactory {

    private static func makeInMemoryContainerUnchecked() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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

        return try completedConstruction(container: container, swiftError: swiftError,
                                         exceptionError: exceptionError)
    }

    static func completedConstruction(container: ModelContainer?, swiftError: Error?,
                                      exceptionError: NSError?) throws -> ModelContainer {
        if exceptionError != nil {
            throw StoreBootstrapBoundaryFailure.indeterminateConstruction
        }
        if let swiftError {
            throw swiftError
        }
        guard let container else {
            throw StoreBootstrapBoundaryFailure.indeterminateConstruction
        }
        return container
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
