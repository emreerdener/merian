import Foundation

/// Wire status values shared by outbox confirmation and its existing callers.
enum ScanCloudStatus: String, Decodable, Equatable, Sendable {
    case found
    case notFound = "not_found"
}

enum ScanIngestionJobStatus: String, Decodable, Equatable, Sendable {
    case processing
    case finalizing
    case retrying
    case failedRetryable = "failed_retryable"
    case failed
    case complete

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "failed_terminal" {
            self = .failed
            return
        }
        guard let status = ScanIngestionJobStatus(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown scan ingestion job status: \(rawValue)"
            )
        }
        self = status
    }
}

enum ComplimentaryScanState: String, Decodable, Equatable, Sendable {
    case held
    case consumed
    case released
}

struct ScanStatusResponse: Decodable, Equatable, Sendable {
    let scanId: String?
    let status: ScanCloudStatus
    let jobStatus: ScanIngestionJobStatus?
    let jobStage: String?
    let jobAttemptCount: Int?
    let retryAfter: String?
    let lastError: String?
    let complimentaryState: ComplimentaryScanState?

    var isFound: Bool { status == .found }

    init(
        scanId: String? = nil,
        status: ScanCloudStatus,
        jobStatus: ScanIngestionJobStatus?,
        jobStage: String?,
        jobAttemptCount: Int?,
        retryAfter: String?,
        lastError: String?,
        complimentaryState: ComplimentaryScanState? = nil
    ) {
        self.scanId = scanId
        self.status = status
        self.jobStatus = jobStatus
        self.jobStage = jobStage
        self.jobAttemptCount = jobAttemptCount
        self.retryAfter = retryAfter
        self.lastError = lastError
        self.complimentaryState = complimentaryState
    }

    private enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case status
        case jobStatus = "job_status"
        case jobStage = "job_stage"
        case jobAttemptCount = "job_attempt_count"
        case retryAfter = "retry_after"
        case lastError = "last_error"
        case complimentaryState = "complimentary_state"
    }
}
