import Foundation
@testable import Merian
import Testing

@Suite("Date Utilities")
struct DateUtilitiesTests {
    @Test func iso8601FormatterOutputsZonedZuluTime() {
        let date = Date(timeIntervalSince1970: 1672531200) // Jan 1, 2023 00:00:00 UTC
        let formatted = DateUtilities.iso8601Formatter.string(from: date)

        #expect(formatted == "2023-01-01T00:00:00Z")
    }

    @Test func iso8601FractionalFormatterIncludesSubsecondPrecision() {
        let date = Date(timeIntervalSince1970: 1672531200.123)
        let formatted = DateUtilities.iso8601FractionalFormatter.string(from: date)

        #expect(
            formatted.hasPrefix("2023-01-01T00:00:00.123Z")
                || formatted.hasPrefix("2023-01-01T00:00:00.122Z")
        )
        #expect(formatted.hasSuffix("Z"))
        #expect(formatted.contains("."))
    }
}
