import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(
    "Scan Repository Account Purge",
    .sharedProcessState(.offlineQueueManager)
)
struct ScanRepositoryPurgeTests {
    @Test func purgeRemovesSpeciesPreferencesAndCompatibilityValues() throws {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.insert(
            UserSpeciesPreference(
                ownerUserID: speciesPreferenceTestUserID,
                scientificName: "Quercus macrocarpa",
                preferredCommonName: "Bur Oak"
            )
        )
        context.insert(
            CapturedMediaEntry(
                orderIndex: 0,
                item: .description(
                    ObservationContext(freeText: "Private observation")
                )
            )
        )
        context.insert(
            OfflineJobRecord(
                id: "species-preference-job",
                kind: .speciesPreferenceSync
            )
        )
        context.insert(
            OfflineQueueEvent(
                jobId: "species-preference-job",
                kind: .queued,
                message: "Pending account work"
            )
        )
        _ = try ObservationHistoryEnrollmentIntent.stage(observationID: UUID(), ownerID: speciesPreferenceTestUserID, context: context)
        context.insert(OfflineJobRecord(id: ObservationHistoryEnrollmentIntent.jobID(UUID().uuidString), kind: .future, status: .cancelled))
        let scan = LocalScanRecord(id: "purge-history", speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(scan)
        context.insert(try LocalAnalysisRecord(
            analysisID: UUID(), observationID: scan.id,
            ownerAccountID: speciesPreferenceTestUserID, completedAt: Date(),
            resultSnapshotData: Data("{\"private_evidence\":\"synthetic\"}".utf8)
        ))
        // Deliberately orphaned state proves account purge is exhaustive even
        // when no parent cascade can reach a partially admitted historical row.
        context.insert(try LocalAnalysisStateRecord(analysisID: UUID(), observationID: UUID().uuidString,
            ownerAccountID: speciesPreferenceTestUserID, observationStateRevision: 1,
            reviewRevision: 0, reviewSnapshotData: Data("{}".utf8)))
        try context.save()

        let suiteName = "merian.tests.account-purge.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        ExploreShareStateStore.setSharedPostId(
            "explore-post",
            for: "scan-id",
            userDefaults: defaults
        )
        FieldNotesStore.setFieldNotes(
            "Private note",
            for: "scan-id",
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.setLegacyPreferredName(
            "White Oak",
            for: "Quercus alba",
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: "Quercus rubra",
            ownerUserID: speciesPreferenceTestUserID,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.recordSyncFailure(
            "Unavailable",
            ownerUserID: speciesPreferenceTestUserID,
            userDefaults: defaults
        )
        defaults.set("dark", forKey: UserDefaultsKeys.themeMode)

        var resetCount = 0
        var runtimeResetCount = 0
        let didPurge = ScanRepository.shared.purgeAllData(
            modelContext: context,
            userDefaults: defaults,
            resetDerivedState: { resetCount += 1 },
            resetRuntimeState: { runtimeResetCount += 1 }
        )

        #expect(didPurge)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisStateRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(resetCount == 1)
        #expect(runtimeResetCount == 1)
        #expect(
            try context.fetch(FetchDescriptor<UserSpeciesPreference>())
                .isEmpty
        )
        #expect(
            try context.fetch(FetchDescriptor<CapturedMediaEntry>()).isEmpty
        )
        #expect(
            try context.fetch(FetchDescriptor<OfflineJobRecord>()).isEmpty
        )
        #expect(
            try context.fetch(FetchDescriptor<OfflineQueueEvent>()).isEmpty
        )
        #expect(!ExploreShareStateStore.hasStoredValues(
            userDefaults: defaults
        ))
        #expect(!FieldNotesStore.hasStoredValues(userDefaults: defaults))
        #expect(!SpeciesPreferredNameStore.hasStoredAccountData(
            userDefaults: defaults
        ))
        #expect(
            defaults.string(forKey: UserDefaultsKeys.themeMode) == "dark"
        )

        #expect(ScanRepository.shared.purgeAllData(
            modelContext: context,
            userDefaults: defaults,
            resetDerivedState: { resetCount += 1 },
            resetRuntimeState: { runtimeResetCount += 1 }
        ))
        #expect(resetCount == 2)
        #expect(runtimeResetCount == 2)
    }

    @Test func purgeInventoryTracksEveryCurrentSchemaEntity() {
        let purgedModelTypes: [any PersistentModel.Type] = [
            LocalScanRecord.self,
            LocalAnalysisRecord.self,
            LocalAnalysisStateRecord.self,
            OfflineQueuedScan.self,
            CapturedMediaEntry.self,
            ScanCollection.self,
            PendingCloudDeletionTask.self,
            UserSpeciesPreference.self,
            OfflineJobRecord.self,
            OfflineQueueEvent.self,
            ActiveOfflineQueuedScanGoalHint.self
        ]

        #expect(
            Set(purgedModelTypes.map(ObjectIdentifier.init))
                == Set(CurrentSchema.models.map(ObjectIdentifier.init)),
            "Every active-schema entity must participate in account purge"
        )

        let purgedModelNames = [
            "CapturedMediaEntry",
            "LocalScanRecord",
            "LocalAnalysisRecord",
            "LocalAnalysisStateRecord",
            "ScanCollection",
            "OfflineQueuedScan",
            "ActiveOfflineQueuedScanGoalHint",
            "PendingCloudDeletionTask",
            "UserSpeciesPreference",
            "OfflineJobRecord",
            "OfflineQueueEvent"
        ]
        let source: String
        do {
            source = try String(
                contentsOf: repositoryRoot()
                    .appendingPathComponent(
                        "apps/ios/Merian/Core/Data/Database/ScanLibraryPurgeService.swift"
                    ),
                encoding: .utf8
            )
        } catch {
            Issue.record(error)
            return
        }

        for modelName in purgedModelNames {
            #expect(source.contains(
                "try modelContext.delete(model: \(modelName).self)"
            ))
        }
        #expect(
            source.components(
                separatedBy: "try modelContext.delete(model:"
            ).count - 1 == purgedModelNames.count,
            "The purge implementation and active-schema inventory diverged"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
