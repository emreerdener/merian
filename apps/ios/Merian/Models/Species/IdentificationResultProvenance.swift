import Foundation

/// Immutable server execution facts. Nil on the enclosing result means legacy;
/// present but undecodable bytes remain unqualified, never legacy by accident.
struct IdentificationResultProvenance: Equatable, Sendable {
    let data: Data

    init(storedData: Data) {
        data = storedData
    }
}
