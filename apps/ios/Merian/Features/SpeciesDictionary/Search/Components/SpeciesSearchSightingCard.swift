import SwiftUI

/// A square public-sighting thumbnail. Public attribution remains available
/// to VoiceOver and in the destination's existing Explore detail presentation.
struct SpeciesSearchSightingCard: View {
    let post: ExplorePost
    let mediaReloadGeneration: UInt64
    var imageDependencies: ExploreHeroImageDependencies = .live
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ExploreHeroImageView(imageUrl: post.gridThumbnailUrl,
                                         reloadGeneration: mediaReloadGeneration, maxDimension: 720,
                                         dependencies: imageDependencies)
                }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if post.hasVideoMedia || post.hasAudioMedia {
                        ExploreMediaTypeIndicator(kind: post.hasVideoMedia ? .video : .audio)
                            .padding(8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Open public sighting")
    }

    private var accessibilitySummary: String {
        var labels = [post.speciesCommonName, post.speciesScientificName,
                      post.authorUsername.map { "@\($0)" } ?? post.authorName]
        if let location = post.publicDisplayLocationLabel { labels.append(location) }
        if let date = post.sharedAtDate {
            labels.append("Shared \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return labels.joined(separator: ", ")
    }
}
