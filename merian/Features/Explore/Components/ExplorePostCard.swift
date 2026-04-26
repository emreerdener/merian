import SwiftUI

struct ExplorePostCard: View {
    let post: ExplorePost
    let onLike: () -> Void
    let onComments: () -> Void
    let onUnshare: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mediaView

            VStack(alignment: .leading, spacing: 16) {
                headerRow
                authorRow
                actionRow
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 10)
    }

    private var mediaView: some View {
        AsyncImage(url: URL(string: post.heroImageUrl)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                ZStack {
                    LinearGradient(
                        colors: [Color(uiColor: .tertiarySystemFill), Color(uiColor: .secondarySystemFill)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            case .empty:
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            @unknown default:
                Color(uiColor: .tertiarySystemFill)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipped()
        .overlay(alignment: .topLeading) {
            if let publicLocationLabel = locationBadgeText {
                ExploreFloatingBadge(
                    text: publicLocationLabel,
                    systemImage: "mappin.and.ellipse"
                )
                .padding(14)
            }
        }
        .overlay(alignment: .topTrailing) {
            menuButton
                .padding(14)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(post.speciesCommonName.capitalized)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text(post.speciesScientificName)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
        }
    }

    private var authorRow: some View {
        HStack(spacing: 10) {
            Label {
                Text(post.authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }

            if let sharedText = sharedAtText {
                Text(sharedText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button(action: onLike) {
                HStack(spacing: 6) {
                    Image(systemName: post.viewerHasLiked ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(post.viewerHasLiked ? .red : .primary)
                    Text(compactCount(post.likeCount))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 16)

            Button(action: onComments) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(compactCount(post.commentCount))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    private var menuButton: some View {
        Menu {
            if post.isOwnedByViewer {
                Button(role: .destructive, action: onUnshare) {
                    Label("Remove from Explore", systemImage: "trash")
                }
            } else {
                Button(role: .destructive, action: onBlock) {
                    Label("Block user", systemImage: "person.crop.circle.badge.xmark")
                }

                Button(role: .destructive, action: onReport) {
                    Label("Report post", systemImage: "flag")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    private var locationBadgeText: String? {
        guard let publicLocationLabel = post.publicLocationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !publicLocationLabel.isEmpty else {
            return nil
        }

        return publicLocationLabel
    }

    private var sharedAtText: String? {
        guard let sharedAtDate = post.sharedAtDate else { return nil }
        return ExplorePostCard.relativeDateFormatter.localizedString(for: sharedAtDate, relativeTo: Date())
    }

    private func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}

private struct ExploreFloatingBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.75)
            )
    }
}
