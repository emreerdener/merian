import Foundation
import SwiftData

/// Current physical liabilities and logical pending packages under a live root
/// and account fence. Both parent reservation and child writes use this audit.
@MainActor
enum SharedMediaCaptureBudget {
    static func evaluate(_ container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                         files: SharedMediaCaptureArtifactFiles, cleanupTarget: UUID? = nil) async throws -> SharedMediaStoragePolicy.Totals {
        let header = try authority.header(container)
        func check() throws {
            guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale }
        }
        return try await SharedMediaCaptureArtifactInspection.withVerified(container: container, profile: authority.profile,
            files: files, cleanupTarget: cleanupTarget, checkpoint: check) { capture in
                try await SharedMediaOrdinaryInspection.withVerifiedCapture(container: container, profile: authority.profile,
                    capture: capture, checkpoint: check) { ordinary in
                        let context = ModelContext(container); context.autosaveEnabled = false
                        let inventory = try inventory(context, profile: authority.profile)
                        var totals = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
                            ownerID: authority.profile.ownerID, format: .appV2, ordinary: ordinary, checkpoint: check).totals
                        // The read audit charges physical liabilities once.
                        // Admission additionally enforces per-observation and
                        // pending-package limits, including prior artifacts.
                        let journals = try SharedMediaCaptureDraftJournalReceipt.inventory(context: context, profile: authority.profile,
                            rootBindingSHA256: files.rootBindingSHA256, checkpoint: check)
                        var packages = journals.packages, offset = 0
                        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(sortBy: [SortDescriptor(\.cursorKey)])
                        query.fetchLimit = SharedMediaStoragePolicy.pageSize
                        while true {
                            try check(); query.fetchOffset = offset
                            let rows = try context.fetch(query)
                            for row in rows {
                                let value = try SharedMediaCaptureArtifactLedger.auditReceipt(row), request = value.request
                                if value.retirement != nil { continue }
                                let generation = request.submissionGeneration, scan = request.scanID
                                var parents = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate {
                                    $0.submissionGeneration == generation || $0.recipientScanID == scan
                                })
                                parents.fetchLimit = 2
                                let found = try context.fetch(parents)
                                if !found.isEmpty {
                                    guard found.count == 1, found.first?.formatRaw == SharedMediaCaptureSubmission.Format.v1.rawValue else {
                                        throw SharedMediaStorageFailure.conflict
                                    }
                                    // Reserved parent packages were already included by the
                                    // scoped budget. Accepted retained cohorts are not pending.
                                    continue
                                }
                                packages[request.scanID] = try SharedMediaStoragePolicy.add(packages[request.scanID, default: 0],
                                    unboundPackageBytes(request))
                                guard packages.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
                            }
                            if rows.count < SharedMediaStoragePolicy.pageSize { break }
                            offset += rows.count
                        }
                        for (id, bytes) in packages { try totals.includePhotoPackage(id: id, bytes: bytes) }
                        return totals
                    }
            }
    }

    nonisolated static func unboundPackageBytes(_ request: SharedMediaCaptureArtifactRequest) throws -> Int64 {
        let headroom = Int64(try request.encoded().count + 64 + SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 64 + 160
            + SharedMediaCaptureRemoteStage.maximumBytes + 64)
        return try SharedMediaStoragePolicy.add(request.byteCount, headroom)
    }

    private static func inventory(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> SharedMediaInventoryRecord {
        let id = profile.inventoryID
        let result = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(result) == profile else { throw SharedMediaStorageFailure.stale }
        return result
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
