import Foundation

/// Input-only cleanup and admission authority. Never authorizes a prepared child,
/// a queue transition, media reconstruction, or provider work.
struct ObservationReanalysisInputReceipt: Equatable, Codable, Sendable {
    enum Phase: String, Codable, Sendable {
        case reserved, fileBound, copied, erasing, complete
    }
    struct Identity: Hashable, Codable, Sendable {
        let device: UInt64
        let inode: UInt64
        let birthSeconds: Int64
        let birthNanoseconds: Int64

        var isValid: Bool {
            inode > 0 && birthSeconds > 0 && (0..<1_000_000_000).contains(birthNanoseconds)
        }
    }
    struct Snapshot: Equatable, Codable, Sendable {
        let byteCount: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        var isValid: Bool {
            byteCount > 0 && byteCount <= Int64(ScanMediaPayloadPolicy.maxSavedVideoBytes)
                && modifiedSeconds > 0 && changedSeconds > 0
                && (0..<1_000_000_000).contains(modifiedNanoseconds)
                && (0..<1_000_000_000).contains(changedNanoseconds)
        }
    }

    static let prefix = "reanalysis-input:"
    static let upperBound = "reanalysis-input;"
    static let maximumReservations = 4
    static let maximumMetadataBytes = 4096
    let version: Int
    let ownerID: UUID
    let parentID: UUID
    let childID: UUID
    let planDigest: String
    let documents: Identity
    let namespace: Identity
    let namespaceGeneration: UUID
    let slot: Int
    let useGeneration: UUID
    let directory: Identity
    let file: Identity?
    let snapshot: Snapshot?
    let phase: Phase
    let retiredPhase: Phase?

    var jobID: String { Self.prefix + childID.uuidString.lowercased() }

    init(ownerID: UUID, parentID: UUID, childID: UUID, planDigest: String,
         documents: Identity, namespace: Identity, namespaceGeneration: UUID,
         slot: Int, useGeneration: UUID, directory: Identity) throws {
        self.init(version: 1, ownerID: ownerID, parentID: parentID, childID: childID,
                  planDigest: planDigest, documents: documents, namespace: namespace,
                  namespaceGeneration: namespaceGeneration, slot: slot, useGeneration: useGeneration,
                  directory: directory, file: nil, snapshot: nil, phase: .reserved, retiredPhase: nil)
        try validate()
    }

    private init(version: Int, ownerID: UUID, parentID: UUID, childID: UUID, planDigest: String,
                 documents: Identity, namespace: Identity, namespaceGeneration: UUID, slot: Int, useGeneration: UUID,
                 directory: Identity, file: Identity?,
                 snapshot: Snapshot?, phase: Phase, retiredPhase: Phase?) {
        self.version = version; self.ownerID = ownerID; self.parentID = parentID; self.childID = childID
        self.planDigest = planDigest; self.documents = documents; self.namespace = namespace
        self.namespaceGeneration = namespaceGeneration; self.slot = slot; self.useGeneration = useGeneration
        self.directory = directory; self.file = file; self.snapshot = snapshot
        self.phase = phase; self.retiredPhase = retiredPhase
    }

    /// Exact replay is checked before charging capacity. A terminal receipt never
    /// becomes a new reservation, even if its original request is replayed.
    func hasSameReservation(as other: Self) -> Bool {
        version == other.version && ownerID == other.ownerID && parentID == other.parentID
            && childID == other.childID && planDigest == other.planDigest
            && documents == other.documents && namespace == other.namespace
            && namespaceGeneration == other.namespaceGeneration && slot == other.slot
            && useGeneration == other.useGeneration && directory == other.directory
    }

    func binding(file identity: Identity) throws -> Self {
        guard phase == .reserved else { throw MerianError.invalidResponse }
        return try changing(phase: .fileBound, file: identity)
    }

    func copied(snapshot value: Snapshot) throws -> Self {
        guard phase == .fileBound else { throw MerianError.invalidResponse }
        return try changing(phase: .copied, snapshot: value)
    }

    func retiring() throws -> Self {
        guard phase != .complete else { throw MerianError.invalidResponse }
        if phase == .erasing { return self }
        return try changing(phase: .erasing, retiredPhase: phase)
    }

    func completed() throws -> Self {
        guard phase == .erasing else { throw MerianError.invalidResponse }
        return try changing(phase: .complete)
    }

    private func changing(phase: Phase, file: Identity? = nil,
                          snapshot: Snapshot? = nil, retiredPhase: Phase? = nil) throws -> Self {
        let value = Self(version: version, ownerID: ownerID, parentID: parentID, childID: childID,
            planDigest: planDigest, documents: documents, namespace: namespace,
            namespaceGeneration: namespaceGeneration, slot: slot, useGeneration: useGeneration,
            directory: directory, file: file ?? self.file, snapshot: snapshot ?? self.snapshot,
            phase: phase, retiredPhase: retiredPhase ?? self.retiredPhase)
        try value.validate()
        return value
    }

    func validate() throws {
        guard version == 1, parentID != childID,
              planDigest.utf8.count == 64,
              planDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              documents.isValid, namespace.isValid, directory.isValid, (0..<Self.maximumReservations).contains(slot),
              Set([documents, namespace, directory]).count == 3 else { throw MerianError.invalidResponse }
        let effective: Phase
        if phase == .erasing || phase == .complete {
            guard let retiredPhase, retiredPhase != .erasing, retiredPhase != .complete else { throw MerianError.invalidResponse }
            effective = retiredPhase
        } else {
            guard retiredPhase == nil else { throw MerianError.invalidResponse }
            effective = phase
        }
        switch effective {
        case .reserved:
            guard file == nil, snapshot == nil else { throw MerianError.invalidResponse }
        case .fileBound:
            guard file?.isValid == true, snapshot == nil else { throw MerianError.invalidResponse }
        case .copied:
            guard file?.isValid == true, snapshot?.isValid == true else { throw MerianError.invalidResponse }
        case .erasing, .complete:
            throw MerianError.invalidResponse
        }
    }

    func encoded() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumMetadataBytes, let text = String(data: data, encoding: .utf8) else {
            throw MerianError.invalidResponse
        }
        return text
    }

    static func decode(_ text: String) throws -> Self {
        guard text.utf8.count <= maximumMetadataBytes else { throw MerianError.invalidResponse }
        let data = Data(text.utf8)
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        // Canonical encoding rejects unknown fields, duplicate keys, null optional
        // fields, noncanonical UUIDs and numeric spelling before authority is used.
        guard try value.encoded() == text else { throw MerianError.invalidResponse }
        return value
    }
}
