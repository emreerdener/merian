import SwiftUI

struct FieldTripPublishedContentItemCard: View {
    let item: FieldTripPublishedContentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldTripRemoteImage(urlString: item.imageURLString)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.prompt)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct FieldTripCommentRow: View {
    let comment: ExploreComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(comment.displayAuthorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                ExploreCommentBodyText(comment: comment, onMentionTap: { _ in })
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = SecureTransportPolicy.httpsURL(
            from: comment.authorAvatarUrl
        ) {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallbackAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAvatar
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 34))
            .foregroundStyle(.secondary)
    }
}

struct FieldTripPublicationErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct FieldTripPublicationSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    itemCard
                }
            }

            comments
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 220, height: 24)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 112, height: 13)
            }

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .frame(height: 15)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 236, height: 15)
            }

            HStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 70, height: 34)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 70, height: 34)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var itemCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 72, height: 10)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(maxWidth: 116)
                    .frame(height: 14)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 104, height: 18)

            ForEach(0..<2, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                            .frame(width: index == 0 ? 96 : 122, height: 12)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.09))
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)
                    }
                }
            }

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)

                Circle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 42, height: 42)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
