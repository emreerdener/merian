import Foundation
import Testing
@testable import Merian

@Suite("Public brand contract")
struct PublicBrandTests {
    @Test func exposesNaturebookAsTheCanonicalPublicIdentity() {
        #expect(PublicBrand.name == "Naturebook")
        #expect(PublicBrand.proName == "Naturebook Pro")
        #expect(PublicBrand.aiName == "Naturebook AI")
        #expect(PublicBrand.websiteURL.absoluteString == "https://naturebook.earth")
        #expect(PublicBrand.supportEmail == "support@naturebook.earth")
        #expect(PublicBrand.canonicalScheme == "naturebook")
    }

    @Test func preservesLegacyLinkCompatibility() {
        #expect(PublicBrand.acceptedSchemes == ["naturebook", "merian"])
        #expect(PublicBrand.acceptedWebHosts == ["naturebook.earth", "merian.earth"])
    }

    @Test func widgetLinksUseTheCanonicalPublicScheme() {
        let link = ExploreWidgetConstants.deepLinkURL(postId: "post-123")
        #expect(link?.absoluteString == "naturebook://explore/post/post-123")
    }
}
