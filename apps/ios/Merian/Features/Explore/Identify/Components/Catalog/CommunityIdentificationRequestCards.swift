import SwiftUI

struct CommunityIdentificationGridCard: View {
    let item: CommunityIdentificationFeedItem

    var body: some View {
        image
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if item.hasVideoMedia {
                    ExploreMediaPlayIndicator()
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                identificationCountBadge
                    .padding(8)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Community identification request")
            .accessibilityValue(identificationCountAccessibilityText)
            .accessibilityHint("Opens request details")
    }

    @ViewBuilder
    private var image: some View {
        if let url = SecureTransportPolicy.httpsURL(from: item.heroImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var identificationCountBadge: some View {
        Label {
            Text(item.identificationCount.formatted(.number.notation(.compactName)))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
        } icon: {
            Image(systemName: "checkmark.bubble.fill")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.black.opacity(0.24), in: Capsule())
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)
        .accessibilityHidden(true)
    }

    private var identificationCountAccessibilityText: String {
        if item.identificationCount == 1 {
            return "1 submitted identification"
        }
        return "\(item.identificationCount) submitted identifications"
    }
}

struct CommunityIdentificationGridCardSkeleton: View {
    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: 0, style: .raisedGrid)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                submittedIdentificationBadgeSkeleton
                    .padding(8)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
    }

    private var submittedIdentificationBadgeSkeleton: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 12, height: 12)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 14, height: 10)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.black.opacity(0.18), in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
    }
}
