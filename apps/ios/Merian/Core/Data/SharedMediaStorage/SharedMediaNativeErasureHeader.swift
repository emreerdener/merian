import Foundation

/// Immutable same-store checkpoint written before any manifest page. The
/// physical owner supplies these audited facts under its held descriptors and
/// accepted account scope; this codec grants neither of those capabilities.
struct SharedMediaNativeErasureHeader: Codable, Equatable, Sendable {
    enum Operation: String, Codable, Sendable { case signOut, accountDeletion }
    static let maximumBytes = 32 * 1024

    let version: Int
    let operation: Operation
    let operationID: UUID
    let profileSHA256: String
    let storeFileIdentity: String
    let storeParentIdentity: String
    let controlParentIdentity: String
    let parentReceiptSHA256: String?
    let controlSHA256: String
    let sourceRevision: Int64
    let sourceTables: [SharedMediaNativeErasureGraph.Table]
    let pageCount: Int64
    let entryCount: Int64
    let lastPageSHA256: String

    @MainActor func encoded(profile: SharedMediaNativeAppProfile) throws -> Data {
        try validate(profile: profile)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    @MainActor static func decode(_ bytes: Data, profile: SharedMediaNativeAppProfile) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: maximumBytes)
        guard try value.encoded(profile: profile) == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    @MainActor private func validate(profile: SharedMediaNativeAppProfile) throws {
        guard version == 1, sourceRevision >= 0, sourceRevision <= Int64.max - 4,
              ![profile.ownerID, profile.inventoryID, profile.generation].contains(operationID),
              profileSHA256 == (try SharedMediaAcquisitionEncoding.digest(profile.binding)),
              [profileSHA256, controlSHA256, lastPageSHA256].allSatisfy(SharedMediaAcquisitionEncoding.isHash),
              parentReceiptSHA256.map(SharedMediaAcquisitionEncoding.isHash) ?? true,
              [storeFileIdentity, storeParentIdentity, controlParentIdentity].allSatisfy(Self.identity),
              sourceTables.map(\.name) == SharedMediaNativeErasureGraph.modelTypes.map({ String(describing: $0) }),
              sourceTables.allSatisfy({ $0.rows >= 0 && SharedMediaAcquisitionEncoding.isHash($0.sha256) }),
              pageCount > 0, pageCount <= entryCount else { throw SharedMediaStorageFailure.invalid }
        // Successful native removals can leave empty package directories after
        // deleting their rows. Entry count is therefore not bounded by row
        // count. The owner audits the marked namespace and builds bounded pages
        // under an explicit scratch-disk budget; the tree checks completeness.
        let (pageCapacity, overflow) = pageCount.multipliedReportingOverflow(by: Int64(SharedMediaNativeErasureManifest.pageSize))
        guard !overflow, entryCount <= pageCapacity else { throw SharedMediaStorageFailure.capacity }
    }

    private static func identity(_ value: String) -> Bool {
        (try? SharedMediaNativeFileIdentity(value + ":0:0:0:0:0")) != nil
    }
}
