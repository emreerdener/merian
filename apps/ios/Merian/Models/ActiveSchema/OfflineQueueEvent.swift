import Foundation
import SwiftData

public enum OfflineQueueEventKind: String, Codable, Sendable, CaseIterable {
    case queued
    case claimed
    case uploadStarted
    case uploadCompleted
    case staged
    case inferenceStarted
    case serverWait
    case retryScheduled
    case completed
    case failed
    case cancelled
    case needsAttention
    case diagnostics
}

@Model
public final class OfflineQueueEvent {
    @Attribute(.unique) public var id: String
    public var jobId: String?
    public var scanId: String?
    public var kindRaw: String
    public var createdAt: Date
    public var message: String?
    public var errorCode: String?
    public var httpStatus: Int?
    public var metadataJSON: String?

    public var kind: OfflineQueueEventKind {
        get { OfflineQueueEventKind(rawValue: kindRaw) ?? .diagnostics }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        id: String = UUID().uuidString,
        jobId: String? = nil,
        scanId: String? = nil,
        kind: OfflineQueueEventKind,
        createdAt: Date = Date(),
        message: String? = nil,
        errorCode: String? = nil,
        httpStatus: Int? = nil,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.jobId = jobId
        self.scanId = scanId
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.message = message
        self.errorCode = errorCode
        self.httpStatus = httpStatus
        self.metadataJSON = metadataJSON
    }
}
