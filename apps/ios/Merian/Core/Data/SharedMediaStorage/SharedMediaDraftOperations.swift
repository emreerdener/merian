import Foundation

/// Uses the existing inbox coordinator; local freeze is not server admission.
@MainActor
struct SharedMediaDraftOperations {
    let storage: SharedMediaStorageRepository
    let io: SharedMediaInboxDestinationIO
    let check: @MainActor () throws -> Void

    func saveMetadata(packageID: UUID, ownerID: UUID, revision: Int64, contexts: [ObservationContext],
                      presentation: [PhotoPreparationImagePresentation]?) throws -> Int64 {
        try check()
        let request = try storage.inboxRead { try $0.drafts.prepareMetadata(packageID: packageID, ownerID: ownerID,
            revision: revision, contexts: contexts, presentation: presentation) }
        do {
            let result = try storage.handoffWrite(before: .beforeMetadataSave, after: .afterMetadataSave,
                requiresFreeSpace: request.growth > 0, additionalFreeBytes: request.growth) { try $0.drafts.saveMetadata(request) }
            try check(); return result
        } catch {
            let result = try storage.inboxRead { try $0.drafts.metadataResult(request) }
            try check(); return result
        }
    }

    func prepare(_ snapshot: PhotoPreparationSnapshot, ownerID: UUID) async throws -> SharedMediaFreezeRequest {
        try check()
        let request = try storage.inboxRead { try $0.drafts.prepareFreeze(snapshot, ownerID: ownerID) }
        try await verify(request)
        _ = try storage.inboxRead { try $0.drafts.requireFreeze(request, ownerID: ownerID, recovered: false) }
        try check(); return request
    }

    func freeze(_ request: SharedMediaFreezeRequest, ownerID: UUID) async throws -> PhotoPreparationReceipt {
        try check()
        let recovered = (try? storage.inboxRead { try $0.drafts.requireFreeze(request, ownerID: ownerID, recovered: true) }) != nil
        _ = try storage.inboxRead { try $0.drafts.requireFreeze(request, ownerID: ownerID, recovered: recovered) }
        try await verify(request)
        if recovered {
            let result = try storage.inboxRead { try $0.drafts.requireFreeze(request, ownerID: ownerID, recovered: true) }
            try check(); return result
        }
        do {
            let result = try storage.handoffWrite(before: .beforeFreezeSave, after: .afterFreezeSave) { try $0.drafts.freeze(request, ownerID: ownerID) }
            try check(); return result
        } catch {
            let result = try storage.inboxRead { try $0.drafts.requireFreeze(request, ownerID: ownerID, recovered: true) }
            try check(); return result
        }
    }

    private func verify(_ request: SharedMediaFreezeRequest) async throws {
        try await io.validate(storage.inboxRead { try $0.photos.inventory() }); try check()
        guard request.files.count == request.identities.count else { throw PhotoPreparationFailure.inconsistentOwnership }
        for (file, identity) in zip(request.files, request.identities) {
            _ = try await io.read(file, identity: identity); try check()
        }
    }
}
