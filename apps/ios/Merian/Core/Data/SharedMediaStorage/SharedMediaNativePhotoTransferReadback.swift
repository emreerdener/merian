import Foundation
import SwiftData

/// Local verified facts only. No payload, reusable file authority or upload grant.
struct SharedMediaNativePhotoTransferReadback: Equatable, Sendable {
    let selection: SharedMediaNativePhotoRoleMapping.Entry
    let byteCount: Int64
    let sha256: String

    @MainActor
    static func state(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                      reservation: SharedMediaNativePhotoTransferReservation,
                      context: ModelContext) throws -> SharedMediaNativePairFileState {
        guard try reservation == SharedMediaNativePhotoTransferReservation(prepared: prepared, selection: reservation.selection) else {
            throw SharedMediaStorageFailure.stale
        }
        let inventoryID = prepared.profile.inventoryID, packageID = prepared.package.id
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let state = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
            package: package, member: member, pairID: reservation.pairID)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        guard state.phase == "ready", state.publishedRevision != nil,
              state.plan.intent == frozen.entries[reservation.selection.photoOrdinal].intent else {
            throw SharedMediaStorageFailure.stale
        }
        return state
    }
}
