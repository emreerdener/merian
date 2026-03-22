import Foundation

public struct DateUtilities {
    /// A reusable `ISO8601DateFormatter` configured with standard internet date-time options.
    /// Accessing this centralized instance prevents expensive, repeated instantiations 
    /// that are known to cause high-frequency memory allocations and CPU spikes.
    public static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    /// A reusable `ISO8601DateFormatter` configured with fractional seconds, 
    /// primarily robust for Supabase / PostgreSQL timestamp deserialization where high precision is required.
    public static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
