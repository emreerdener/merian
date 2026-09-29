import Foundation

/// Immutable server execution facts. Nil on the enclosing result means legacy;
/// present but undecodable bytes remain unqualified, never legacy by accident.
struct IdentificationResultProvenance: Equatable, Sendable {
    let data: Data

    var requiresPrimaryIdentification: Bool {
        struct ContractIdentity: Decodable { let schema: String }
        guard data.count <= 2_048,
              let identity = try? JSONDecoder().decode(ContractIdentity.self, from: data) else { return false }
        return identity.schema == "merian_identify_primary_v1"
    }

    init(storedData: Data) {
        data = storedData
    }
}
