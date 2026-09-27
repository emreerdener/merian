import Testing
import UIKit

@testable import Merian

@MainActor
struct LinkShareItemSourceTests {
    @Test func everyDestinationReceivesTheURLInsteadOfATextAttachment() throws {
        let url = try #require(URL(string: "https://naturebook.earth/explore/post/test-post"))
        let source = LinkShareItemSource(url: url, title: "Listen to this bird")
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)

        #expect(source.activityViewControllerPlaceholderItem(controller) as? URL == url)
        let activities: [UIActivity.ActivityType?] = [
            nil, .airDrop, .copyToPasteboard, .message, .mail,
            .addToReadingList, UIActivity.ActivityType("third-party-extension")
        ]
        for activity in activities {
            let item = source.activityViewController(controller, itemForActivityType: activity)
            #expect(item as? URL == url)
            #expect(item as? String == nil)
        }

        let metadata = try #require(source.activityViewControllerLinkMetadata(controller))
        #expect(metadata.url == url)
        #expect(metadata.originalURL == url)
        #expect(metadata.title == "Listen to this bird")
        #expect(source.activityViewController(controller, subjectForActivityType: .mail) == metadata.title)
    }
}
