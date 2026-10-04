import Foundation
import SwiftData

/// Inventory runs after producer admission closes. Runnable counts deliberately
/// exclude failed work and must never authorize an identity replacement.
struct LibraryMutationInventory: Equatable, Sendable {
    let queuedScans: Int
    let pendingJobs: Int
    let attentionJobs: Int
    let pendingDeletions: Int
    let collectionTombstones: Int
    let goalHints: Int
    var localOnlyChanges: Int = 0

    var isReady: Bool {
        queuedScans == 0 && pendingJobs == 0 && attentionJobs == 0
            && pendingDeletions == 0 && collectionTombstones == 0 && goalHints == 0 && localOnlyChanges == 0
    }

    var issue: LibraryTransitionIssue? {
        guard !isReady else { return nil }
        return attentionJobs > 0 || localOnlyChanges > 0 ? .needsAttention : .pendingChanges
    }

    /// First launch seeds one empty Favorites collection before Auth finishes.
    /// It is presentation scaffolding, not evidence of an outgoing library.
    @MainActor
    static func isEmptyLibrary(in container: ModelContainer, userDefaults: UserDefaults = .standard) throws -> Bool {
        let context = ModelContext(container)
        guard try read(from: container, userDefaults: userDefaults).isReady,
              try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0 else { return false }
        let collections = try context.fetch(FetchDescriptor<ScanCollection>())
        return collections.isEmpty || (collections.count == 1
            && collections[0].name == "Favorites"
            && !collections[0].isPendingDeletion
            && (collections[0].scans?.isEmpty ?? true))
    }

    @MainActor
    static func read(from container: ModelContainer, sourceUserID: UUID? = nil, userDefaults: UserDefaults = .standard) throws -> Self {
        let context = ModelContext(container)
        let complete = OfflineJobStatus.complete.rawValue
        let cancelled = OfflineJobStatus.cancelled.rawValue
        let attention = OfflineJobStatus.needsAttention.rawValue
        // Local desired state must match an operation-specific acknowledgment,
        // including legacy details not yet represented by a durable outbox.
        let records = try context.fetch(FetchDescriptor<LocalScanRecord>())
        let tagJobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter { $0.id.hasPrefix("library-details:") }
        var acknowledged: [String: [LibraryDetailsSyncService.Mutation]] = [:]
        var acknowledgedNotes: [String: [String?]] = [:]
        for job in tagJobs {
            guard job.status == .complete, let json = job.metadataJSON,
                  let mutation = try? JSONDecoder().decode(LibraryDetailsSyncService.Mutation.self, from: Data(json.utf8)),
                  mutation.ownerID == sourceUserID else { continue }
            acknowledged[mutation.scanID, default: []].append(mutation)
            if mutation.fieldNotes != nil || job.id.hasPrefix("library-details:baseline:") {
                acknowledgedNotes[mutation.scanID, default: []].append(mutation.fieldNotes)
            }
        }
        var localOnlyChanges = records.filter { record in
            let favorite = record.collections?.contains { $0.name == "Favorites" } == true
            guard record.fieldNotes?.isEmpty == false || !record.customTags.isEmpty || favorite else { return false }
            return !(acknowledged[record.id] ?? []).contains { mutation in
                mutation.tags == record.customTags && mutation.fieldNotes == record.fieldNotes && mutation.isFavorite == favorite
            }
        }.count
        let localNotes = Dictionary(records.compactMap { record in
            record.fieldNotes.map { (record.id, $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }, uniquingKeysWith: { first, _ in first })
        // Once restored/acknowledged, the model supersedes the legacy bridge,
        // including a remote clear. Unknown/orphaned bridge values still block.
        let authoritativeScanIDs = Set(records.filter { acknowledgedNotes[$0.id]?.contains($0.fieldNotes) == true }.map(\.id))
        localOnlyChanges += FieldNotesStore.unrepresentedValueCount(
            scanNotes: localNotes, authoritativeScanIDs: authoritativeScanIDs, userDefaults: userDefaults
        )
        let preferences = try context.fetch(FetchDescriptor<UserSpeciesPreference>())
        if let sourceUserID {
            let acknowledged = SpeciesPreferredNameStore.acknowledgedValues(ownerUserID: sourceUserID, userDefaults: userDefaults)
            localOnlyChanges += preferences.filter {
                $0.ownerUserId != sourceUserID.uuidString.lowercased() || acknowledged[$0.scientificName] != $0.preferredCommonName
            }.count
            localOnlyChanges += SpeciesPreferredNameStore.pendingDeleteDates(ownerUserID: sourceUserID, userDefaults: userDefaults).count
        } else {
            localOnlyChanges += preferences.count
        }
        return try Self(
            queuedScans: context.fetchCount(FetchDescriptor<OfflineQueuedScan>()),
            pendingJobs: context.fetchCount(FetchDescriptor<OfflineJobRecord>(
                predicate: #Predicate { $0.statusRaw != complete && $0.statusRaw != cancelled }
            )),
            attentionJobs: context.fetchCount(FetchDescriptor<OfflineJobRecord>(
                predicate: #Predicate { $0.statusRaw == attention }
            )),
            pendingDeletions: context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()),
            collectionTombstones: context.fetchCount(FetchDescriptor<ScanCollection>(
                predicate: #Predicate { $0.isPendingDeletion }
            )),
            goalHints: context.fetchCount(FetchDescriptor<ActiveOfflineQueuedScanGoalHint>()),
            localOnlyChanges: localOnlyChanges
        )
    }
}
