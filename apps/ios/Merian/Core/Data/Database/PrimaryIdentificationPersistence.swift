import Foundation

/// Shared integrity boundary for first completion, duplicate completion and
/// history reconciliation. No review state can rewrite the original AI answer.
enum PrimaryIdentificationPersistence {
    static func validateMerge(
        storedPrimary: Data?, storedProvenance: Data?,
        incomingPrimary: PrimaryIdentification?, incomingProvenance: IdentificationResultProvenance?
    ) throws {
        let stored = PrimaryIdentification.restoring(
            stored: storedPrimary,
            provenance: storedProvenance.map(IdentificationResultProvenance.init(storedData:))
        )
        let incoming = PrimaryIdentification.restoring(
            stored: incomingPrimary?.data, provenance: incomingProvenance
        )
        if let stored, stored.value == nil { throw PrimaryIdentification.IntegrityError.invalidSnapshot }
        if let incoming, incoming.value == nil { throw PrimaryIdentification.IntegrityError.invalidSnapshot }
        _ = try PrimaryIdentification.merging(stored: storedPrimary, incoming: incoming)
        if stored != nil || incoming != nil,
           let storedProvenance, let incomingProvenance {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let before = try decoder.decode(IdentificationProvenanceDTO.self, from: storedProvenance)
            let after = try decoder.decode(IdentificationProvenanceDTO.self, from: incomingProvenance.data)
            guard try encoder.encode(before) == encoder.encode(after) else {
                throw PrimaryIdentification.IntegrityError.conflictingSnapshot
            }
        }
    }
}
