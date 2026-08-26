import SwiftUI

struct ExplorePostDetailAuthorHeader: View {
    let post: ExplorePost
    let avatarUrl: URL?
    let locationText: String?
    let opensAuthorProfile: Bool
    let onOpenAuthorProfile: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            authorAvatarView

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(authorDisplayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if shouldShowAuthorProBadge {
                        MerianProBadge()
                    }
                }
                .accessibilityElement(children: .combine)

                if let locationText {
                    Text(locationText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard opensAuthorProfile else { return }
            onOpenAuthorProfile()
        }
    }

    @ViewBuilder
    private var authorAvatarView: some View {
        if let avatarUrl {
            AsyncImage(url: avatarUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackAuthorAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAuthorAvatar
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            fallbackAuthorAvatar
        }
    }

    private var fallbackAuthorAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(.primary)
    }

    private var authorDisplayName: String {
        post.authorDisplayName(preferUsername: true)
    }

    private var shouldShowAuthorProBadge: Bool {
        post.authorIsPro == true
            || (post.isOwnedByViewer && RevenueCatManager.shared.isSubscribed)
    }
}

struct ExplorePostDetailActionRow: View {
    let viewerHasLiked: Bool
    let likeCountText: String
    let commentCountText: String
    let onLike: () -> Void
    let onComments: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            ExploreDetailActionButton(
                systemImage: viewerHasLiked ? "heart.fill" : "heart",
                value: likeCountText,
                isHighlighted: viewerHasLiked,
                action: onLike
            )

            ExploreDetailActionButton(
                systemImage: "bubble.right",
                value: commentCountText,
                isHighlighted: false,
                action: onComments
            )

            Spacer(minLength: 12)

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share post")
        }
    }
}

struct ExplorePostDetailSpeciesSummary: View {
    let scientificName: String
    let postCommonName: String
    let displayCommonName: String
    let aiReasoning: AttributedString?
    let onCommonNameMaxYChange: (CGFloat) -> Void

    private var shouldShowScientificName: Bool {
        !scientificName.isEmpty
            && scientificName.lowercased() != postCommonName.lowercased()
            && scientificName != "Taxonomy Unavailable"
    }

    private var normalizedScientificName: String {
        scientificName
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if shouldShowScientificName {
                Text(normalizedScientificName)
                    .font(.system(.title3))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(displayCommonName)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(
                                of: geo.frame(in: .named("ExplorePostDetailScrollSpace")).maxY,
                                initial: true
                            ) { _, newMaxY in
                                onCommonNameMaxYChange(newMaxY)
                            }
                    }
                )

            if let aiReasoning {
                Text(aiReasoning)
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 8)
            }

        }
        .frame(maxWidth: .infinity)
    }
}
