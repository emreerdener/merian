import Foundation
import SwiftData

/// Transient display composition over the existing native owner. It owns no
/// files, work lifetime, submission, durable state, or execution authority.
@MainActor
enum NativeInitialInsightMedia {
    static func app(scanID: String, bindingID: UUID, container: ModelContainer,
                    di: AppDIContainer, isPresentedCurrent: @escaping @MainActor () -> Bool,
                    publish: @MainActor (ActiveScanMedia) throws -> Void) async throws {
        let manager = di.supabaseManager
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let accountID = manager.currentUser?.id else { throw SharedMediaStorageFailure.closed }
        let generation = manager.authSessionGeneration
        let current = {
            isPresentedCurrent() && manager.currentUser?.id == accountID && manager.authSessionGeneration == generation
                && di.offlineQueueManager.modelContext?.container === container
                && !manager.libraryAccountRecoveryRequired && !manager.librarySignOutRecoveryPending
                && (manager.libraryTransferResult == .completed || manager.isGuestUser)
        }
        _ = try await read(scanID: scanID, bindingID: bindingID, container: container,
            owner: { try await di.nativeMediaOwnerForFeature() }, isCurrent: current, publish: publish)
    }

    static func read(scanID: String, bindingID: UUID, container: ModelContainer,
                     owner: @escaping @MainActor () async throws -> SharedMediaNativeOriginalOwner,
                     isCurrent: @escaping @MainActor () -> Bool,
                     publish: @MainActor (ActiveScanMedia) throws -> Void = { _ in }) async throws -> ActiveScanMedia {
        func check() throws {
            try Task.checkCancellation()
            guard isCurrent(), try binding(scanID: scanID, container: container) == bindingID else {
                throw SharedMediaStorageFailure.stale
            }
        }
        try check()
        guard let observationID = UUID(uuidString: scanID), observationID.uuidString.lowercased() == scanID else {
            throw SharedMediaStorageFailure.stale
        }
        let native = try await owner(); try check()
        let prepared = try await native.appReceivingQuery(
            SharedMediaNativeReceivingQuery.retainedInitial(observationID: observationID, bindingID: bindingID))
        try check()
        let readback = try await native.readRetainedAppPhotos(prepared, role: .display)
        try check()
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(
            readback.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try supporting.encoded() == readback.supportingBytes else { throw SharedMediaStorageFailure.conflict }
        // A deletion intent can appear without changing the binding. Re-read
        // the complete existing Applied witness after the last await; publish
        // synchronously before any further actor suspension.
        let fresh = try SharedMediaNativeReceivingQuery.retainedInitial(observationID: observationID, bindingID: bindingID)
            .read(container, profile: prepared.profile)
        guard try fresh.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
        let media = ActiveScanMedia(items: readback.photos.map { .retainedDisplayImage(id: $0.pairID, data: $0.bytes) }
            + supporting.contexts.map { .description($0) })
        try Task.checkCancellation()
        try publish(media)
        return media
    }

    static func binding(scanID: String, container: ModelContainer) throws -> UUID {
        let context = ModelContext(container); context.autosaveEnabled = false
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanID }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first,
              case .nativeInitial(let binding) = try SharedMediaConsumerAuthority.classify(
                raw: row.mediaAuthorityRaw, consumerID: row.sharedMediaConsumerID, record: .scan) else {
            throw SharedMediaStorageFailure.stale
        }
        return binding
    }
}
