import Foundation

/// Authentication can succeed while the source library still needs recovery.
enum LibraryTransferResult: String, Codable, Equatable, Sendable {
    case completed
    case pending
    case needsAttention
}
