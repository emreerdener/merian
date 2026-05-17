import Foundation
import SwiftData

@Model
public final class ScanCollection {
    @Attribute(.unique) public var id: String = UUID().uuidString
    public var name: String
    public var createdAt: Date = Date()
    public var isDeleted: Bool = false

    @Relationship(inverse: \LocalScanRecord.collections) public var scans: [LocalScanRecord]? = []

    public init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), isDeleted: Bool = false, scans: [LocalScanRecord]? = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isDeleted = isDeleted
        self.scans = scans
    }
}
