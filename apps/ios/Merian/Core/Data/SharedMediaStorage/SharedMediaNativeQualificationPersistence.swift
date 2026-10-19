import Foundation
import SwiftData

/// Existing V1 orchestration only. The caller supplies the repository's sealed
/// authority; no factory, file authority or V2 conversion is available here.
@MainActor
enum SharedMediaNativeQualificationPersistence {
    static func settle(container: ModelContainer, inventoryID: UUID, grant: SharedMediaNativeSettlementGrant,
                       authority: SharedMediaNativeMutationAuthority,
                       boundary: (SharedMediaNativeAcquisitionBoundary) throws -> Void) throws -> SharedMediaAcquisitionResult? {
        let reader = SharedMediaNativeOriginalReadback(container: container, inventoryID: inventoryID, authority: authority)
        try boundary(.beforeReadback)
        guard let saved = try reader.receipt(grant.request) else {
            guard !grant.loaderStarted else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
        switch saved {
        case .completed(_, let result): return result
        case .held: return nil
        case .reserved:
            do {
                let transaction = try SharedMediaNativeAcquisitionMutation.hold(container: container,
                    request: grant.request, authority: authority)
                try boundary(.beforeHeldSave); try transaction.save(); try boundary(.afterHeldSave)
            } catch { /* Exact saved acknowledgement below; no writer replay. */ }
            try boundary(.beforeReadback)
            guard case .held = try reader.receipt(grant.request) else { throw SharedMediaStorageFailure.conflict }
            return nil
        case .released: throw SharedMediaStorageFailure.conflict
        }
    }

    static func metadata(container: ModelContainer, request: SharedMediaNativeMetadataRequest,
                         authority: SharedMediaNativeMutationAuthority, available: Int64,
                         boundary: (SharedMediaNativeMetadataBoundary) throws -> Void) throws -> Int64 {
        func read() throws -> SharedMediaNativeMetadataMutation {
            try authority.validate(); try boundary(.beforeReadback)
            return try .init(container: container, inventoryID: request.inventoryID, packageID: request.packageID, authority: authority)
        }
        do {
            _ = try read().apply(request, availableBytes: available,
                beforeSave: { try boundary(.beforeSave) }, afterSave: { try boundary(.afterSave) })
        } catch {
            let failure = error
            do { return try read().result(request) } catch { throw failure }
        }
        return try read().result(request)
    }
}
