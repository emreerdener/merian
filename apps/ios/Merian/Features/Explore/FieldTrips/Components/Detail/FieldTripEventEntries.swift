import SwiftUI

struct FieldTripChallengeEntriesSection: View {
    let entries: [FieldTripChallengeEntry]
    let hasMoreEntries: Bool
    let isLoadingMore: Bool
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Challenge entries")
                .font(.headline.weight(.bold))

            if entries.isEmpty {
                Text("No published entries yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            } else {
                ForEach(entries) { entry in
                    FieldTripChallengeEntryCard(
                        entry: entry,
                        onOpenEntry: onOpenEntry,
                        onOpenAuthorProfile: onOpenAuthorProfile
                    )
                }

                if hasMoreEntries {
                    Button(action: onLoadMore) {
                        HStack(spacing: 8) {
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text("Load more")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingMore)
                }
            }
        }
    }
}

struct FieldTripChallengeEntryCard: View {
    let entry: FieldTripChallengeEntry
    let onOpenEntry: (String) -> Void
    let onOpenAuthorProfile: (FieldTripChallengeEntry) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenEntry(entry.entryId)
            } label: {
                FieldTripCoverImage(
                    urlString: entry.coverImageUrl,
                    templateSlug: entry.templateSlug
                )
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Label("Field trip", systemImage: "map")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Button {
                    onOpenEntry(entry.entryId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(entry.challengeTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenAuthorProfile(entry)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                        Text(entry.publicAuthorDisplayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                FieldTripTagRow(tags: Array((entry.regionTags + entry.habitatTags).prefix(3)))

                HStack(spacing: 10) {
                    Label("\(entry.itemCount)", systemImage: "leaf")
                    Label(entry.likeCount.formatted(), systemImage: "heart")
                    Label(entry.commentCount.formatted(), systemImage: "bubble.left")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                onOpenEntry(entry.entryId)
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
