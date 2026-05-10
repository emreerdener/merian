import SwiftUI
import UIKit
import WidgetKit

struct ExploreImageEntry: TimelineEntry {
    let date: Date
    let item: ExploreWidgetItem?
}

struct ExploreImageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExploreImageEntry {
        ExploreImageEntry(date: Date(), item: nil)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ExploreImageEntry) -> Void
    ) {
        let item = context.isPreview ? nil : loadItems().first
        completion(ExploreImageEntry(date: Date(), item: item))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ExploreImageEntry>) -> Void
    ) {
        let now = Date()
        let items = loadItems()

        guard !items.isEmpty else {
            let entry = ExploreImageEntry(date: now, item: nil)
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(now.addingTimeInterval(ExploreWidgetConstants.emptyStateRefreshInterval))
                )
            )
            return
        }

        let entries = items.enumerated().map { offset, item in
            ExploreImageEntry(
                date: now.addingTimeInterval(Double(offset) * ExploreWidgetConstants.rotationInterval),
                item: item
            )
        }

        completion(
            Timeline(
                entries: entries,
                policy: .after(
                    now.addingTimeInterval(Double(items.count) * ExploreWidgetConstants.rotationInterval)
                )
            )
        )
    }

    private func loadItems() -> [ExploreWidgetItem] {
        let fileManager = FileManager.default
        let snapshot = ExploreWidgetCache.loadSnapshot(fileManager: fileManager)

        return snapshot?.items.filter { item in
            guard let imageURL = ExploreWidgetConstants.imageURL(
                for: item.imageFilename,
                fileManager: fileManager
            ) else {
                return false
            }

            return fileManager.fileExists(atPath: imageURL.path)
        } ?? []
    }
}

struct ExploreImageWidgetView: View {
    let entry: ExploreImageEntry

    var body: some View {
        ZStack {
            Color.black
            imageView
        }
        .containerBackground(for: .widget) {
            Color.black
        }
        .widgetURL(entry.item.flatMap { ExploreWidgetConstants.deepLinkURL(postId: $0.postId) })
    }

    @ViewBuilder
    private var imageView: some View {
        if let image = entry.item.flatMap(loadImage) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Color.black
        }
    }

    private func loadImage(for item: ExploreWidgetItem) -> UIImage? {
        guard let url = ExploreWidgetConstants.imageURL(for: item.imageFilename) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }
}

struct ExploreImageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ExploreWidgetConstants.kind,
            provider: ExploreImageTimelineProvider()
        ) { entry in
            ExploreImageWidgetView(entry: entry)
        }
        .configurationDisplayName("Explore")
        .description("Cycles through recent Explore discoveries.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct MerianExploreWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExploreImageWidget()
    }
}
