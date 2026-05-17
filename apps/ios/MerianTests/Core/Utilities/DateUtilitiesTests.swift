import Testing
import Foundation
@testable import Merian

struct DateUtilitiesTests {
    
    @Test func testISO8601FormatterOutputsZonedZuluTime() {
        let date = Date(timeIntervalSince1970: 1672531200) // Jan 1, 2023 00:00:00 UTC
        let formatted = DateUtilities.iso8601Formatter.string(from: date)
        
        #expect(formatted == "2023-01-01T00:00:00Z")
    }
    
    @Test func testISO8601FractionalFormatterIncludesSubsecondPrecision() {
        // Use a date with known fractional components
        let date = Date(timeIntervalSince1970: 1672531200.123) 
        let formatted = DateUtilities.iso8601FractionalFormatter.string(from: date)
        
        // Assert it strictly format to three digits of precision with Z
        #expect(formatted.hasPrefix("2023-01-01T00:00:00.123Z") || formatted.hasPrefix("2023-01-01T00:00:00.122Z")) 
        // Note: floating point rounding locally can sometimes produce .122Z or .123Z so we just assert suffix shape basically
        #expect(formatted.hasSuffix("Z"))
        #expect(formatted.contains("."))
    }
}
