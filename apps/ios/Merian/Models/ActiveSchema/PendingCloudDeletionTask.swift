import Foundation
import SwiftData

@Model
public final class PendingCloudDeletionTask {
    @Attribute(.unique) public var scanId: String
    public var timestamp: Date = Date()

    public init(scanId: String, timestamp: Date = Date()) {
        self.scanId = scanId
        self.timestamp = timestamp
    }
}
