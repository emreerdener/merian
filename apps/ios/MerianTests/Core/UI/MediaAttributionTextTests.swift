import Foundation
import Testing

@testable import Merian

@Suite("Readable media attribution")
struct MediaAttributionTextTests {
    @Test func embeddedLinksKeepCreditsAndDestinations() {
        let website = "http://www.example.org/flowers/yellow.htm"
        let license = "https://creativecommons.org/licenses/by-sa/3.0/"
        let credit = MediaAttributionText.formatted("Émile Example · \(website) · \(license) · Wikipedia")

        #expect(String(credit.characters) == "Émile Example · Website · CC BY-SA 3.0 · Wikipedia")
        #expect(credit.runs.compactMap(\.link).map(\.absoluteString) == [website, license])
    }

    @Test(arguments: [
        ("https://creativecommons.org/licenses/by/3.0/au/", "CC BY 3.0 AU"),
        ("http://creativecommons.org/publicdomain/zero/1.0/", "CC0 1.0"),
        ("https://creativecommons.org/publicdomain/mark/1.0/", "Public domain"),
        ("https://creativecommons.org/licenses/by-nc-sa/4.0/deed.en", "CC BY-NC-SA 4.0"),
        ("https://creativecommons.org/unknown", "License"),
        ("https://creativecommons.org.example.org/licenses/by/4.0/", "Website"),
        ("www.example.org/credit", "Website"),
        ("example.org/credit", "Website"),
        ("ftp://example.org/credit", "Website"),
        ("mailto:creator@example.org", "Contact"),
        ("MAILTO:creator@example.org", "Contact")
    ])
    func readableLinkLabels(input: String, expected: String) {
        let credit = MediaAttributionText.formatted(input)
        #expect(String(credit.characters) == expected)
        #expect(credit.runs.compactMap(\.link).count == 1)
        if input.contains("://") || input.lowercased().hasPrefix("mailto:") {
            #expect(credit.runs.compactMap(\.link).first == URL(string: input))
        }
    }

    @Test func plainCreditsAreUnchanged() {
        for label in ["@field_author · Naturebook", "Example Photographer · CC BY 4.0 · GBIF", "first.last@example.org", "Wikipedia", ""] {
            let credit = MediaAttributionText.formatted(label)
            #expect(String(credit.characters) == label)
            #expect(credit.runs.compactMap(\.link).isEmpty)
        }
    }

    @Test func punctuationAndRepeatedLinksSurvive() {
        let credit = MediaAttributionText.formatted("Photo (https://example.org/credit), https://example.org/credit.")
        #expect(String(credit.characters) == "Photo (Website), Website.")
        #expect(credit.runs.compactMap(\.link).count == 2)
    }
}
