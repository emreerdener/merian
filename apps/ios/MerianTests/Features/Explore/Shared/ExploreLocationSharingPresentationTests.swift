import Testing

@testable import Merian

@Suite("Explore Location Sharing Presentation")
struct ExploreLocationSharingPresentationTests {
    @Test func casesRetainVisibleCopyAndSymbols() {
        #expect(ExplorePostLocationSharing.allCases == [.open, .obscured, .privateLocation])

        #expect(ExplorePostLocationSharing.open.title == "Open")
        #expect(ExplorePostLocationSharing.open.systemImage == "mappin.and.ellipse")
        #expect(ExplorePostLocationSharing.open.detail == "Show broad label and add to Explore Map.")

        #expect(ExplorePostLocationSharing.obscured.title == "Obscured")
        #expect(ExplorePostLocationSharing.obscured.systemImage == "location.viewfinder")
        #expect(ExplorePostLocationSharing.obscured.detail == "Show broad label and keep off Explore Map.")

        #expect(ExplorePostLocationSharing.privateLocation.title == "Private")
        #expect(ExplorePostLocationSharing.privateLocation.systemImage == "location.slash")
        #expect(ExplorePostLocationSharing.privateLocation.detail == "Share this post without public location.")
    }
}
