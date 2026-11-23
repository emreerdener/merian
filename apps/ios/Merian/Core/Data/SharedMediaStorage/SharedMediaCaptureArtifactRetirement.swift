import Foundation

/// Permanent cleanup intent for one parentless source. This value never grants
/// byte reads, upload, source adoption or a new writer identity. It is persisted
/// before unlink and kept after absence is proven, so an interrupted cleanup
/// cannot turn back into capture work.
struct SharedMediaCaptureArtifactRetirement: Codable, Equatable, Sendable {
    static let maximumBytes = 8192
    let version: Int
    let requestSHA256: String
    let inventoryRevision: Int64
    let partialIdentity: String?
    let finalIdentity: String?
    let releasedRevision: Int64?
    let preparationSHA256: String?

    init(request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage?,
         inventoryRevision: Int64, partialIdentity: String?, finalIdentity: String?, preparationSHA256: String? = nil) throws {
        version = preparationSHA256 == nil ? 1 : 2; requestSHA256 = try request.digest
        self.preparationSHA256 = preparationSHA256
        self.inventoryRevision = inventoryRevision
        self.partialIdentity = partialIdentity; self.finalIdentity = finalIdentity
        releasedRevision = nil
        try validate(request: request, stage: stage)
    }

    private init(_ prior: Self, releasedRevision: Int64) {
        version = prior.version; requestSHA256 = prior.requestSHA256
        inventoryRevision = prior.inventoryRevision
        partialIdentity = prior.partialIdentity; finalIdentity = prior.finalIdentity
        self.releasedRevision = releasedRevision
        preparationSHA256 = prior.preparationSHA256
    }

    func releasing(at revision: Int64, request: SharedMediaCaptureArtifactRequest,
                   stage: SharedMediaCaptureArtifactStage?) throws -> Self {
        guard releasedRevision == nil else { throw SharedMediaStorageFailure.conflict }
        let result = Self(self, releasedRevision: revision)
        try result.validate(request: request, stage: stage)
        return result
    }

    func validate(request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage?) throws {
        try request.validate()
        let minimumRevision = try stage?.inventoryRevision ?? SharedMediaStoragePolicy.add(request.inventoryRevision, 1)
        switch version {
        case 1:
            guard request.format == .draftSourceV1, preparationSHA256 == nil else { throw SharedMediaStorageFailure.conflict }
        case 2:
            guard request.format == .v1, !request.role.rawValue.hasPrefix("source_"),
                  let preparationSHA256, SharedMediaAcquisitionEncoding.isHash(preparationSHA256) else {
                throw SharedMediaStorageFailure.conflict
            }
        default: throw SharedMediaStorageFailure.conflict
        }
        guard requestSHA256 == (try request.digest), partialIdentity == nil || finalIdentity == nil,
              inventoryRevision > minimumRevision,
              inventoryRevision < Int64.max,
              releasedRevision.map({ $0 > inventoryRevision && $0 < Int64.max }) ?? true else {
            throw SharedMediaStorageFailure.conflict
        }
        if let stage {
            try stage.validate(request)
            let recorded = try Self.identity(stage.partialIdentity)
            if stage.phase == .complete {
                guard partialIdentity == nil, finalIdentity == stage.finalIdentity else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard let present = partialIdentity ?? finalIdentity else { throw SharedMediaStorageFailure.conflict }
                let observed = try Self.identity(present)
                guard observed.inode == recorded.inode, observed.bytes <= request.byteCount,
                      finalIdentity == nil || observed.bytes == request.byteCount else { throw SharedMediaStorageFailure.conflict }
            }
        } else {
            // A reserved source may have crashed after creating its empty
            // partial but before recording an inode. It can only be deleted.
            guard finalIdentity == nil else { throw SharedMediaStorageFailure.conflict }
            if let partialIdentity {
                guard try Self.identity(partialIdentity).bytes == 0 else { throw SharedMediaStorageFailure.conflict }
            }
        }
        for value in [partialIdentity, finalIdentity].compactMap({ $0 }) { _ = try Self.identity(value) }
    }

    func encoded(request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage?) throws -> Data {
        try validate(request: request, stage: stage)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    static func decode(_ data: Data, sha256: String, request: SharedMediaCaptureArtifactRequest,
                       stage: SharedMediaCaptureArtifactStage?) throws -> Self {
        guard data.count <= maximumBytes, SharedMediaAcquisitionEncoding.isHash(sha256),
              SharedMediaAcquisitionEncoding.digest(data) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: maximumBytes)
        guard try value.encoded(request: request, stage: stage) == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    private static func identity(_ value: String) throws -> (inode: String, bytes: Int64) {
        guard value.utf8.count <= 160 else { throw SharedMediaStorageFailure.conflict }
        let fields = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7, let device = Int32(fields[0]), String(device) == fields[0],
              let inode = UInt64(fields[1]), inode > 0, String(inode) == fields[1],
              let bytes = Int64(fields[2]), bytes >= 0, String(bytes) == fields[2] else { throw SharedMediaStorageFailure.conflict }
        for index in 3...6 {
            guard let number = Int64(fields[index]), String(number) == fields[index],
                  index % 2 != 0 || (0...999_999_999).contains(number) else { throw SharedMediaStorageFailure.conflict }
        }
        return (fields[0] + ":" + fields[1], bytes)
    }
}
