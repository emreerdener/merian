import Foundation
@testable import Merian
import Testing

@Suite("App Share Content Tests")
struct AppShareContentTests {
    @Test func prelaunchDestinationUsesServedWebsiteRoot() {
        #expect(AppShareContent.destinationURL == PublicBrand.websiteURL)
        #expect(
            AppShareContent.destinationURL.absoluteString
                == "https://naturebook.earth"
        )
        #expect(AppShareContent.destinationURL.scheme == "https")
        #expect(AppShareContent.destinationURL.host == "naturebook.earth")
        #expect(AppShareContent.destinationURL.path.isEmpty)
    }

    @Test func sharePayloadIncludesCopyAndURL() {
        let items = AppShareContent.activityItems
        let textItems = items.compactMap { $0 as? String }
        let urlItems = items.compactMap { $0 as? URL }

        #expect(textItems.count == 1)
        #expect(urlItems == [AppShareContent.destinationURL])
        #expect(textItems.first?.contains(AppShareContent.title) == true)
        #expect(textItems.first?.contains(AppShareContent.message) == true)
    }
}
