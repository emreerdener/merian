import os

enum MerianLog {
    static let auth = Logger(subsystem: "com.merian.app", category: "Auth")
    static let network = Logger(subsystem: "com.merian.app", category: "Network")
    static let data = Logger(subsystem: "com.merian.app", category: "Data")
    static let hardware = Logger(subsystem: "com.merian.app", category: "Hardware")
    static let exploreVideo = Logger(subsystem: "com.merian.app", category: "ExploreVideo")
    static let general = Logger(subsystem: "com.merian.app", category: "General")

    /// Returns only the bounded static error type for operational diagnostics.
    /// Error descriptions can contain account identifiers, provider payloads,
    /// request URLs, and other customer data, so authentication and purchase
    /// code must never interpolate an `Error` instance directly into logs.
    static func errorKind(_ error: Error) -> String {
        let raw = String(describing: type(of: error))
        let sanitized = raw.map { character in
            if character.isLetter || character.isNumber || character == "." || character == "_" {
                return character
            }
            return "_"
        }
        let bounded = String(sanitized.prefix(80))
        return bounded.isEmpty ? "UnknownError" : bounded
    }
}
