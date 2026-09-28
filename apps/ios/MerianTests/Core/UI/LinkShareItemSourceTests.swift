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
        #expect(metadata.imageProvider == nil)
        #expect(source.activityViewController(controller, subjectForActivityType: .mail) == metadata.title)
    }

    @Test func previewProviderLoadsAnImageWithoutChangingTheSharedURL() async throws {
        let url = try #require(URL(string: "https://naturebook.earth/explore/post/test-post"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let source = LinkShareItemSource(url: url, title: "A discovery") { image }
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        let metadata = try #require(source.activityViewControllerLinkMetadata(controller))
        let provider = try #require(metadata.imageProvider)
        #expect(provider.canLoadObject(ofClass: UIImage.self))
        let loaded: UIImage? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        #expect(try #require(loaded).size == image.size)
        #expect(source.activityViewController(controller, itemForActivityType: .message) as? URL == url)
        #expect(source.activityViewController(controller, itemForActivityType: .airDrop) as? URL == url)
    }

    @Test func unavailablePreviewCompletesWithAnErrorAndKeepsTheLink() async throws {
        let url = try #require(URL(string: "https://naturebook.earth/explore/post/test-post"))
        let source = LinkShareItemSource(url: url, title: "A discovery") { nil }
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        let metadata = try #require(source.activityViewControllerLinkMetadata(controller))
        let provider = try #require(metadata.imageProvider)
        let failed: Bool = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, error in
                continuation.resume(returning: object == nil && error != nil)
            }
        }
        #expect(failed)
        #expect(source.activityViewController(controller, itemForActivityType: .message) as? URL == url)
    }
}
