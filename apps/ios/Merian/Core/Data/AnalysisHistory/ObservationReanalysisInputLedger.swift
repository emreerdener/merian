import Foundation

/// Bounded active occupancy in the existing erasure persistence owner. Completed
/// child receipts remain independent immutable replay records; admission reads
/// only this control and at most four referenced receipts.
struct ObservationReanalysisInputLedger: Equatable, Codable, Sendable {
    typealias Receipt = ObservationReanalysisInputReceipt
    enum State: String, Codable, Sendable { case initial, active, released }
    struct Slot: Equatable, Codable, Sendable {
        let index: Int
        let directory: Receipt.Identity
        let state: State
        let childID: UUID?
        let useGeneration: UUID?
    }

    static let jobID = "reanalysis-input-ledger:v1"
    static let ownershipLowerBound = "reanalysis-input"
    static let ownershipUpperBound = "reanalysis-inpuu"
    static let maximumMetadataBytes = 8192
    let version: Int
    let namespaceGeneration: UUID
    let documents: Receipt.Identity
    let namespace: Receipt.Identity
    let slots: [Slot]

    /// Only the FileStore's exclusively locked fresh-namespace bootstrap may
    /// supply these identities. An absent row is never sufficient authority.
    init(namespaceGeneration: UUID, documents: Receipt.Identity, namespace: Receipt.Identity,
         directories: [Receipt.Identity]) throws {
        self.init(version: 1, namespaceGeneration: namespaceGeneration, documents: documents, namespace: namespace,
            slots: directories.enumerated().map { Slot(index: $0.offset, directory: $0.element,
                state: .initial, childID: nil, useGeneration: nil) })
        try validate()
    }

    private init(version: Int, namespaceGeneration: UUID, documents: Receipt.Identity,
                 namespace: Receipt.Identity, slots: [Slot]) {
        self.version = version; self.namespaceGeneration = namespaceGeneration
        self.documents = documents; self.namespace = namespace; self.slots = slots
    }

    func validate() throws {
        guard version == 1, documents.isValid, namespace.isValid,
              slots.count == Receipt.maximumReservations,
              slots.enumerated().allSatisfy({ $0.offset == $0.element.index && $0.element.directory.isValid }),
              Set([documents, namespace] + slots.map(\.directory)).count == Receipt.maximumReservations + 2 else {
            throw MerianError.invalidResponse
        }
        var children = Set<UUID>(), generations = Set<UUID>()
        for slot in slots {
            switch slot.state {
            case .initial:
                guard slot.childID == nil, slot.useGeneration == nil else { throw MerianError.invalidResponse }
            case .active, .released:
                guard let child = slot.childID, let generation = slot.useGeneration,
                      children.insert(child).inserted, generations.insert(generation).inserted else { throw MerianError.invalidResponse }
            }
        }
    }

    /// Validate every referenced receipt freshly. A raw released flag, missing
    /// link or mismatched generation never establishes a free slot.
    func validate(_ receipt: Receipt, for slot: Slot) throws {
        try receipt.validate()
        guard slot.index >= 0, slot.index < slots.count, slots[slot.index] == slot,
              receipt.namespaceGeneration == namespaceGeneration,
              receipt.documents == documents, receipt.namespace == namespace,
              receipt.slot == slot.index, receipt.directory == slot.directory,
              receipt.childID == slot.childID, receipt.useGeneration == slot.useGeneration else {
            throw ObservationHistoryError.resultConflict
        }
        switch slot.state {
        case .initial: throw ObservationHistoryError.resultConflict
        case .active:
            guard receipt.phase != .complete else { throw ObservationHistoryError.resultConflict }
        case .released:
            guard receipt.phase == .complete else { throw ObservationHistoryError.resultConflict }
        }
    }

    func reserving(_ receipt: Receipt, prior: Receipt?) throws -> Self {
        try validate(); try receipt.validate()
        guard receipt.phase == .reserved, slots.indices.contains(receipt.slot) else { throw MerianError.invalidResponse }
        let slot = slots[receipt.slot]
        guard receipt.namespaceGeneration == namespaceGeneration, receipt.documents == documents,
              receipt.namespace == namespace, receipt.directory == slot.directory,
              !slots.contains(where: { $0.childID == receipt.childID || $0.useGeneration == receipt.useGeneration }) else {
            throw ObservationHistoryError.resultConflict
        }
        switch slot.state {
        case .initial:
            guard prior == nil else { throw ObservationHistoryError.resultConflict }
        case .released:
            guard let prior else { throw ObservationHistoryError.resultConflict }
            try validate(prior, for: slot)
        case .active:
            throw ObservationHistoryError.unavailable
        }
        var changed = slots
        changed[slot.index] = Slot(index: slot.index, directory: slot.directory, state: .active,
            childID: receipt.childID, useGeneration: receipt.useGeneration)
        let result = Self(version: version, namespaceGeneration: namespaceGeneration,
            documents: documents, namespace: namespace, slots: changed)
        try result.validate()
        return result
    }

    /// The caller atomically saves this ledger and the completed child receipt
    /// after irreversible retirement and fsynced unlink under the exact slot lock.
    func releasing(_ retiring: Receipt, completed: Receipt) throws -> Self {
        try validate()
        guard retiring.phase == .erasing, try retiring.completed() == completed,
              slots.indices.contains(retiring.slot) else { throw ObservationHistoryError.resultConflict }
        let slot = slots[retiring.slot]
        guard slot.state == .active else { throw ObservationHistoryError.resultConflict }
        try validate(retiring, for: slot)
        var changed = slots
        changed[slot.index] = Slot(index: slot.index, directory: slot.directory, state: .released,
            childID: retiring.childID, useGeneration: retiring.useGeneration)
        let result = Self(version: version, namespaceGeneration: namespaceGeneration,
            documents: documents, namespace: namespace, slots: changed)
        try result.validate()
        return result
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
        let value = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        try value.validate()
        guard try value.encoded() == text else { throw MerianError.invalidResponse }
        return value
    }
}
