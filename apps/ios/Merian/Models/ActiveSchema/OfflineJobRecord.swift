import Foundation
import SwiftData

public enum OfflineJobKind: String, Codable, Sendable, CaseIterable {
    case scanIngestion
    case cloudDeletion
    case collectionSync
    case speciesPreferenceSync
    case future
}

public enum OfflineJobStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case waiting
    case needsAttention
    case complete
    case cancelled
}

@Model
public final class OfflineJobRecord {
    @Attribute(.unique) public var id: String
    public var kindRaw: String
    public var subjectId: String?
    public var priority: Int
    public var statusRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastAttemptAt: Date?
    public var nextRunAt: Date?
    public var attemptCount: Int
    public var lastErrorCode: String?
    public var lastErrorMessage: String?
    public var lastHTTPStatus: Int?
    public var serverStatus: String?
    public var serverStage: String?
    public var serverRetryAfter: Date?
    public var requiresUnconstrainedNetwork: Bool
    public var allowsCellular: Bool
    public var approximateBytes: Int64
    public var metadataJSON: String?

    public var kind: OfflineJobKind {
        get { OfflineJobKind(rawValue: kindRaw) ?? .future }
        set { kindRaw = newValue.rawValue }
    }

    public var status: OfflineJobStatus {
        get { OfflineJobStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        id: String,
        kind: OfflineJobKind,
        subjectId: String? = nil,
        priority: Int = 0,
        status: OfflineJobStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        nextRunAt: Date? = nil,
        attemptCount: Int = 0,
        lastErrorCode: String? = nil,
        lastErrorMessage: String? = nil,
        lastHTTPStatus: Int? = nil,
        serverStatus: String? = nil,
        serverStage: String? = nil,
        serverRetryAfter: Date? = nil,
        requiresUnconstrainedNetwork: Bool = false,
        allowsCellular: Bool = true,
        approximateBytes: Int64 = 0,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.subjectId = subjectId
        self.priority = priority
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAttemptAt = lastAttemptAt
        self.nextRunAt = nextRunAt
        self.attemptCount = attemptCount
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
        self.lastHTTPStatus = lastHTTPStatus
        self.serverStatus = serverStatus
        self.serverStage = serverStage
        self.serverRetryAfter = serverRetryAfter
        self.requiresUnconstrainedNetwork = requiresUnconstrainedNetwork
        self.allowsCellular = allowsCellular
        self.approximateBytes = approximateBytes
        self.metadataJSON = metadataJSON
    }
}
