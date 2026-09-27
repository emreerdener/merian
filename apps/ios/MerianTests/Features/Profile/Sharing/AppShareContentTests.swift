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

    @MainActor
    @Test func sharePayloadUsesOneLinkWithPreviewCopy() throws {
        let items = AppShareContent.activityItems
        let source = try #require(items.first as? LinkShareItemSource)
        #expect(items.count == 1)
        #expect(source.url == AppShareContent.destinationURL)
        #expect(source.title == AppShareContent.title)
    }
}
