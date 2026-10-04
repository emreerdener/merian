import Foundation
import SwiftData

@MainActor
enum LibraryDetailsSyncService {
    struct Mutation: Codable, Equatable, Sendable {
        let ownerID: UUID
        let scanID: String
        let tags: [String]
        let operationID: UUID
        let fieldNotes: String?
        let isFavorite: Bool
    }

    static func stage(_ record: LocalScanRecord, ownerID: UUID, context: ModelContext) throws {
        let mutation = Mutation(ownerID: ownerID, scanID: record.id, tags: record.customTags, operationID: UUID(),
                                fieldNotes: record.fieldNotes,
                                isFavorite: record.collections?.contains { $0.name == "Favorites" } == true)
        try stage(mutation: mutation, context: context)
    }

    private static func stage(mutation: Mutation, context: ModelContext) throws {
        let job = try context.ensureOfflineJobRecord(
            id: "library-details:\(mutation.operationID.uuidString.lowercased())", kind: .future, subjectId: mutation.scanID
        )
        job.metadataJSON = String(bytes: try JSONEncoder().encode(mutation), encoding: .utf8)
        job.status = .pending
        job.updatedAt = Date()
    }

    /// Called only after the server proves source retirement and destination
    /// ownership. The retained merge proof fences local edits until this save.
    static func finalizeTransfer(from source: UUID, to destination: UUID, context: ModelContext) throws {
        let write = ModelContext(context.container)
        write.autosaveEnabled = false
        for job in try write.fetch(FetchDescriptor<OfflineJobRecord>()) where job.id.hasPrefix("library-details:") {
            guard let json = job.metadataJSON else { throw LibraryTransferPersistenceError.unreadable }
            let mutation = try JSONDecoder().decode(Mutation.self, from: Data(json.utf8))
            guard mutation.ownerID == source else { continue }
            guard job.status == .complete || job.status == .cancelled else { throw LibraryTransferPersistenceError.pending }
            let rebound = Mutation(ownerID: destination, scanID: mutation.scanID, tags: mutation.tags,
                                   operationID: mutation.operationID, fieldNotes: mutation.fieldNotes, isFavorite: mutation.isFavorite)
            job.metadataJSON = String(bytes: try JSONEncoder().encode(rebound), encoding: .utf8)
        }
        let sourceID = source.uuidString.lowercased()
        // The backend resolved preference conflicts. Retire only the source's
        // acknowledged read cache and restore the destination's authoritative rows.
        for preference in try write.fetch(FetchDescriptor<UserSpeciesPreference>(predicate: #Predicate { $0.ownerUserId == sourceID })) {
            write.delete(preference)
        }
        try write.save()
    }

    enum LibraryTransferPersistenceError: Error { case unreadable, pending }

    private static var isDraining = false

    /// Import legacy notes before unrelated tag/favorite operations can clear
    /// them. Only a restored baseline proves an old bridge value was cleared.
    static func stageLegacyDetails(context: ModelContext, ownerID: UUID, userDefaults: UserDefaults = .standard, scanID: String? = nil) throws {
        let jobDescriptor: FetchDescriptor<OfflineJobRecord>
        let scanDescriptor: FetchDescriptor<LocalScanRecord>
        if let scanID {
            jobDescriptor = FetchDescriptor(predicate: #Predicate { $0.subjectId == scanID })
            scanDescriptor = FetchDescriptor(predicate: #Predicate { $0.id == scanID })
        } else {
            jobDescriptor = FetchDescriptor()
            scanDescriptor = FetchDescriptor()
        }
        let jobs = try context.fetch(jobDescriptor).filter { $0.id.hasPrefix("library-details:") }
        let decoded = jobs.compactMap { job -> (OfflineJobRecord, Mutation)? in
            guard job.status != .cancelled, let json = job.metadataJSON,
                  let mutation = try? JSONDecoder().decode(Mutation.self, from: Data(json.utf8)),
                  mutation.ownerID == ownerID else { return nil }
            return (job, mutation)
        }
        let byScan = Dictionary(grouping: decoded, by: { $0.1.scanID })
        for record in try context.fetch(scanDescriptor) {
            let operations = byScan[record.id] ?? []
            let latestPending = operations.filter { $0.0.status != .complete }.max { lhs, rhs in
                lhs.0.createdAt == rhs.0.createdAt ? lhs.0.id < rhs.0.id : lhs.0.createdAt < rhs.0.createdAt
            }?.1
            let latestDesired = latestPending ?? operations.max { lhs, rhs in
                lhs.0.updatedAt == rhs.0.updatedAt ? lhs.0.id < rhs.0.id : lhs.0.updatedAt < rhs.0.updatedAt
            }?.1
            if let latestPending {
                try restoreDesiredProjection(latestPending, into: record, context: context)
            }
            let hasRestoredNotes = operations.contains { job, mutation in
                job.status == .complete && job.id.hasPrefix("library-details:baseline:") && mutation.fieldNotes == record.fieldNotes
            }
            var importedLegacyNotes = false
            if !hasRestoredNotes, record.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
               let legacyNotes = FieldNotesStore.fieldNotes(for: record.id, userDefaults: userDefaults) {
                record.fieldNotes = latestDesired?.fieldNotes ?? legacyNotes
                importedLegacyNotes = true
            }
            // Existing immutable operations own desired state. A stale read
            // projection must not manufacture an edit that overwrites them.
            guard operations.isEmpty || importedLegacyNotes else { continue }
            let tags = importedLegacyNotes ? latestDesired?.tags ?? record.customTags : record.customTags
            let favorite = (importedLegacyNotes ? latestDesired?.isFavorite : nil)
                ?? (record.collections?.contains { $0.name == "Favorites" } == true)
            let alreadyStaged = operations.contains { _, mutation in
                mutation.fieldNotes == record.fieldNotes && mutation.tags == tags && mutation.isFavorite == favorite
            }
            if !alreadyStaged, record.fieldNotes?.isEmpty == false || !tags.isEmpty || favorite {
                let mutation = Mutation(ownerID: ownerID, scanID: record.id, tags: tags, operationID: UUID(),
                                        fieldNotes: record.fieldNotes, isFavorite: favorite)
                try restoreDesiredProjection(mutation, into: record, context: context)
                try stage(mutation: mutation, context: context)
            }
        }
        try context.save()
    }

    private static func restoreDesiredProjection(_ mutation: Mutation, into record: LocalScanRecord, context: ModelContext) throws {
        record.fieldNotes = mutation.fieldNotes
        record.customTags = mutation.tags
        let isFavorite = record.collections?.contains { $0.name == "Favorites" } == true
        guard isFavorite != mutation.isFavorite else { return }
        var collections = record.collections ?? []
        collections.removeAll { $0.name == "Favorites" }
        if mutation.isFavorite {
            let favorites = try context.fetch(FetchDescriptor<ScanCollection>(predicate: #Predicate { $0.name == "Favorites" }))
            let favorite = favorites.first ?? ScanCollection(name: "Favorites")
            if favorites.isEmpty { context.insert(favorite) }
            collections.append(favorite)
        }
        record.collections = collections
    }

    static func drain(context: ModelContext, manager: SupabaseManager) async {
        guard !Task.isCancelled, !isDraining, manager.ensureLibraryAccountOwnership() else { return }
        isDraining = true
        defer { isDraining = false }
        guard let lease = try? manager.beginUnownedAccountBoundWork() else { return }
        defer { manager.finishAccountBoundWork(lease) }
        OfflineJobScheduler.shared.libraryDetailsDrainDidStart(using: .shared)
        await drainPending(
            context: context, ownerID: lease.session.userID,
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent(lease) },
            requestRetry: { OfflineJobScheduler.shared.scheduleLibraryDetailsRetry(using: .shared) },
            send: { mutation in
                try await manager.client.rpc("set_owned_scan_library_details", params: LibraryDetailsRequest(
                    p_scan_id: mutation.scanID, p_custom_tags: mutation.tags, p_operation_id: mutation.operationID,
                    p_field_notes: mutation.fieldNotes, p_is_favorite: mutation.isFavorite
                )).execute()
            }
        )
    }

    /// Re-read after every batch: producers may enqueue while a request
    /// is suspended, and their wake-up is coalesced by the live drain's latch.
    static func drainPending(
        context: ModelContext,
        ownerID: UUID,
        userDefaults: UserDefaults = .standard,
        isCurrent: () -> Bool,
        requestRetry: () -> Void = {},
        send: (Mutation) async throws -> Void,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) async {
        // An admitted attempt can be cancelled before or during its request.
        // Retain a wake rather than treating cancellation as queue completion.
        defer {
            if Task.isCancelled, isCurrent() { requestRetry() }
        }
        do {
            guard isCurrent(), !Task.isCancelled else { return }
            try stageLegacyDetails(context: context, ownerID: ownerID, userDefaults: userDefaults)
            let complete = OfflineJobStatus.complete.rawValue
            let cancelled = OfflineJobStatus.cancelled.rawValue
            while isCurrent(), !Task.isCancelled {
                let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>(
                    predicate: #Predicate { $0.statusRaw != complete && $0.statusRaw != cancelled },
                    sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)]
                )).filter { $0.id.hasPrefix("library-details:") }
                guard !jobs.isEmpty else { return }
                for job in jobs {
                    guard isCurrent(), !Task.isCancelled else { return }
                    guard job.status != .cancelled, job.modelContext != nil else { continue }
                    guard let json = job.metadataJSON,
                          let mutation = try? JSONDecoder().decode(Mutation.self, from: Data(json.utf8)),
                          mutation.ownerID == ownerID else { return }
                    try await send(mutation)
                    guard isCurrent(), !Task.isCancelled else { return }
                    guard job.metadataJSON == json, job.status != .cancelled, job.modelContext != nil else { continue }
                    let previousStatus = job.statusRaw
                    job.status = .complete
                    do {
                        try save(context)
                    } catch {
                        // Keep memory consistent with the failed durable acknowledgment.
                        job.statusRaw = previousStatus
                        throw error
                    }
                }
            }
        } catch {
            // Keep the immutable operation, including on ambiguous server success.
            // Retrying the same operation ID cannot apply an older edit twice.
            if isCurrent(), !Task.isCancelled { requestRetry() }
        }
    }
}

private struct LibraryDetailsRequest: Encodable {
    let p_scan_id: String
    let p_custom_tags: [String]
    let p_operation_id: UUID
    let p_field_notes: String?
    let p_is_favorite: Bool
    enum CodingKeys: String, CodingKey {
        case p_scan_id, p_custom_tags, p_operation_id, p_field_notes, p_is_favorite
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(p_scan_id, forKey: .p_scan_id)
        try values.encode(p_custom_tags, forKey: .p_custom_tags)
        try values.encode(p_operation_id, forKey: .p_operation_id)
        try values.encode(p_field_notes, forKey: .p_field_notes)
        try values.encode(p_is_favorite, forKey: .p_is_favorite)
    }
}
