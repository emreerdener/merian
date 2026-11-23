import Foundation

/// Constructed once with a new observation request, never during result replay.
/// Submitted evidence remains separate from the resulting editable note.
enum InitialFieldNotesSeed {
    static func make(contexts: [ObservationContext]) -> String? {
        let description = contexts.map { $0.serialized() }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return description.isEmpty ? nil : description
    }
}
