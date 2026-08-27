import SwiftUI

struct ExploreAuthorProfileHeaderCard: View {
    let profile: ExploreAuthorProfile
    let visibleAwards: [AwardPayload]
    let earnedPatches: [EarnedFieldTripPatch]
    let showsProBadge: Bool
    let onOpenFieldTrip: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ExploreAuthorAvatar(url: profile.authorAvatarURL, size: 48)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(profile.profileTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityAddTraits(.isHeader)

                        if showsProBadge {
                            MerianProBadge()
                        }
                    }

                    if let username = profile.publicUsernameDisplayName {
                        Text(username)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }

            Divider()
            summaryCounts

            if !earnedPatches.isEmpty {
                Divider()
                EarnedFieldTripPatchCarousel(
                    patches: earnedPatches,
                    onOpenFieldTrip: onOpenFieldTrip
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var summaryCounts: some View {
        HStack(spacing: 0) {
            summaryCount(profile.heatmap.totalCaptures, label: "Scans")
            summaryCount(visibleAwards.filter(\.isCompleted).count, label: "Achievements")
            summaryCount(profile.followerCount, label: "Followers")
            summaryCount(profile.followingCount, label: "Following")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func summaryCount(_ count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(count.formatted(.number.notation(.compactName)))
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ExploreAuthorProfileFollowButton: View {
    let isFollowing: Bool
    let isUpdating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isFollowing ? "checkmark" : "person.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                }

                Text(isFollowing ? "Following" : "Follow")
                    .font(.headline)
            }
            .foregroundStyle(isFollowing ? .primary : Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isFollowing ? Color(uiColor: .secondarySystemGroupedBackground) : Color.primary)
            )
            .overlay(
                Capsule()
                    .stroke(isFollowing ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .accessibilityLabel(isFollowing ? "Following" : "Follow")
        .padding(.top, 2)
    }
}
