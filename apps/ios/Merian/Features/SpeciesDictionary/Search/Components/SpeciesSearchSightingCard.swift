import SwiftUI

/// The Dictionary's public-sighting tile with the same Explore media and
/// privacy-filtered author/location values, plus an explicit publication date.
struct SpeciesSearchSightingCard: View {
    let post: ExplorePost
    let mediaReloadGeneration: UInt64
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                ExploreHeroImageView(imageUrl: post.gridThumbnailUrl,
                                     reloadGeneration: mediaReloadGeneration, maxDimension: 720)
                    .aspectRatio(1.4, contentMode: .fill)
                    .frame(maxHeight: 240)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if post.hasVideoMedia || post.hasAudioMedia {
                            ExploreMediaTypeIndicator(kind: post.hasVideoMedia ? .video : .audio)
                                .padding(10)
                        }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(post.speciesCommonName).font(.headline)
                    Text(post.speciesScientificName).font(.subheadline).italic().foregroundStyle(.secondary)
                    Text(post.authorUsername.map { "@\($0)" } ?? post.authorName)
                        .font(.caption).foregroundStyle(.secondary)
                    if let label = post.publicDisplayLocationLabel {
                        Label(label, systemImage: "mappin").font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = post.sharedAtDate {
                        Text("Shared \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding([.horizontal, .bottom], 12)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open public sighting")
    }
}
