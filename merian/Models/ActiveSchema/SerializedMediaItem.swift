import Foundation

/// A serializable representation of captured media elements, preserving chronological order
/// across image, audio, and textual modalities for persistent storage.
enum SerializedMediaItem: Codable, Equatable {
    case image(String)
    case audio(String)
    case description(ObservationContext)
}
