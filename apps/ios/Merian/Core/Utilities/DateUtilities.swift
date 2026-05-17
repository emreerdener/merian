import Foundation

public struct DateUtilities {
    /// Shared formatter for standard ISO 8601 date-time strings.
    /// Reusing a single instance avoids the overhead of repeated `ISO8601DateFormatter` allocation.
    public static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// Shared formatter for ISO 8601 timestamps with fractional seconds.
    /// Used for Supabase/PostgreSQL timestamps that include sub-second precision.
    public static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
