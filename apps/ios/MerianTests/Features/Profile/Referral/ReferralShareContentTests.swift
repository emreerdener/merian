import Foundation
@testable import Merian
import Testing

@Suite("Referral Share Content Tests")
struct ReferralShareContentTests {
    @Test func placeholderURLUsesSingleInviteConstant() {
        #expect(ReferralShareContent.url.absoluteString == "https://merian.earth/invite")
        #expect(ReferralShareContent.url.scheme == "https")
        #expect(ReferralShareContent.url.host == "merian.earth")
        #expect(ReferralShareContent.url.path == "/invite")
    }

    @Test func sharePayloadIncludesCopyAndURL() {
        let items = ReferralShareContent.activityItems
        let textItems = items.compactMap { $0 as? String }
        let urlItems = items.compactMap { $0 as? URL }

        #expect(textItems.count == 1)
        #expect(urlItems == [ReferralShareContent.url])
        #expect(textItems.first?.contains(ReferralShareContent.title) == true)
        #expect(textItems.first?.contains(ReferralShareContent.message) == true)
    }
}
