import Foundation

// MARK: - Inference Task Identity

struct InferenceURLSessionTaskIdentity: Sendable, Equatable {
    let scanId: String
    let generation: UUID?
    /// Auth user whose JWT authorized the inference request. `nil` is accepted
    /// only for legacy task parsing and is treated as unknown/fail-closed at an
    /// account transition boundary.
    let ownerUserID: UUID?

    init(
        scanId: String,
        generation: UUID?,
        ownerUserID: UUID? = nil
    ) {
        self.scanId = scanId
        self.generation = generation
        self.ownerUserID = ownerUserID
    }
}

/// Optional guard used by queue deletion paths that originate from inference work.
///
/// The wrapper is itself optional so `nil` can continue to mean "explicit,
/// unguarded deletion", while `InferenceGenerationExpectation(generation: nil)`
/// means "delete only while this scan still has no in-process generation".
struct InferenceGenerationExpectation: Sendable, Equatable {
    let generation: UUID?
}

// MARK: - Inference Persistence

/// Guard used when queue cleanup originates from a foreground inference attempt.
///
/// Foreground inference begins before recovery media necessarily reaches R2, so it
/// cannot use the background-only `.inferencing` state as its ownership fence. Its
/// generation is instead persisted on the scan-ingestion job in the same transaction
/// that creates the queued scan and compared again before persistence or deletion.
struct ForegroundInferenceGenerationExpectation: Sendable, Equatable {
    let generation: UUID
}

/// Durable ownership supplied to live-result persistence.
struct LiveInferencePersistenceFence: Sendable, Equatable {
    let scanId: String
    let generation: UUID
}

/// Separates a successful save from the valid "not a new discovery" result.
///
/// The previous Boolean return value conflated those states, allowing queue cleanup
/// to continue after persistence was rejected or failed.
struct LiveInferencePersistenceResult: Sendable, Equatable {
    let wasSaved: Bool
    let isNewDiscovery: Bool

    static let notSaved = LiveInferencePersistenceResult(
        wasSaved: false,
        isNewDiscovery: false
    )
}

// MARK: - Funding

enum ScanFundingSource: String, Codable, Sendable, Equatable {
    case paidPro = "paid_pro"
    case complimentaryPro = "complimentary_pro"
    case immediateFlash = "immediate_flash"
    case deferredFlash = "deferred_flash"
}

/// Idempotent local admission decision tied to one account and stable scan ID.
struct ScanFundingReservation: Codable, Sendable, Equatable {
    let accountId: UUID
    let scanId: String
    var source: ScanFundingSource
    var blockerScanIds: [String]
    let createdAt: Date

    init(
        accountId: UUID,
        scanId: String,
        source: ScanFundingSource,
        blockerScanIds: [String] = [],
        createdAt: Date = Date()
    ) {
        self.accountId = accountId
        self.scanId = scanId.lowercased()
        self.source = source
        self.blockerScanIds = blockerScanIds.map { $0.lowercased() }
        self.createdAt = createdAt
    }

    var allowsDispatch: Bool { source != .deferredFlash }
    var allowsForegroundInference: Bool { source != .deferredFlash }

    private enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case scanId = "scan_id"
        case source
        case blockerScanIds = "blocker_scan_ids"
        case createdAt = "created_at"
    }
}

// MARK: - Background Account Ownership

enum BackgroundAccountWorkPhase: String, Codable, Sendable, Equatable {
    case upload
    case inference
}

/// Durable account/generation owner for a background URLSession operation.
///
/// URLSession tasks can outlive both the creating process and its Auth
/// session. This record is the local write fence: a callback must match it and
/// the queue state before it may stage media, persist inference, or delete
/// queued work.
struct BackgroundAccountWorkOwnership: Codable, Sendable, Equatable {
    let ownerUserID: UUID
    let generation: UUID
    let phase: BackgroundAccountWorkPhase

    private enum CodingKeys: String, CodingKey {
        case ownerUserID = "owner_user_id"
        case generation
        case phase
    }
}

struct BackgroundAccountWorkCandidate: Sendable, Equatable {
    let scanId: String
    let ownership: BackgroundAccountWorkOwnership
}
