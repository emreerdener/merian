import SwiftUI

struct FieldTripCommunityPublicationCard: View {
    let publication: FieldTripRecentPublication
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenPublication(publication.publicationId)
            } label: {
                FieldTripCoverImage(
                    urlString: publication.coverImageUrl,
                    templateSlug: publication.slug
                )
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Button {
                    onOpenPublication(publication.publicationId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(publication.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(
                            FieldTripTemplatePresentation.title(
                                publication.templateTitle,
                                slug: publication.slug
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenAuthorProfile(publication)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                        Text(publication.publicAuthorDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                FieldTripTagRow(tags: Array((publication.regionTags + publication.habitatTags).prefix(3)))

                HStack(spacing: 10) {
                    Label("\(publication.itemCount)", systemImage: "leaf")
                    Label(publication.likeCount.formatted(), systemImage: "heart")
                    Label(publication.commentCount.formatted(), systemImage: "bubble.left")
                    if let reason = publication.communityReasonLabel {
                        Label(reason, systemImage: reason == "Following" ? "person.fill.checkmark" : "sparkle")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                onOpenPublication(publication.publicationId)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
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
