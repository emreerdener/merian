import SwiftUI

struct CommunityIdentificationActivityRow: View {
    let item: CommunityIdentificationActivityItem

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: activitySymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(activityColor, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2)
                        }
                        .offset(x: 4, y: 4)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if hasTaxon {
                    Text(item.displayName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !relativeTimestamp.isEmpty {
                    Text(relativeTimestamp)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the identification request")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = SecureTransportPolicy.httpsURL(from: item.thumbnailUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                case .failure:
                    placeholder
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
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        switch item.activityType {
        case .suggestionBurst:
            suggestionSummary
        case .consensusChanged:
            "Community consensus changed"
        case .resolved:
            "Community identified this request"
        }
    }

    private var suggestionSummary: String {
        let actors = item.recentActorNames
        let count = max(item.suggestionCount, 1)

        guard !actors.isEmpty else {
            return count == 1 ? "Someone suggested an ID" : "\(count) new ID suggestions"
        }
        if count == 1 {
            return "\(actors[0]) suggested an ID"
        }
        if actors.count == 1 {
            return "\(actors[0]) added \(count) ID suggestions"
        }
        if actors.count == 2 {
            return "\(actors[0]) and \(actors[1]) added \(count) ID suggestions"
        }
        return "\(actors[0]), \(actors[1]), and others added \(count) ID suggestions"
    }

    private var hasTaxon: Bool {
        item.taxonCommonName != nil || item.taxonScientificName != nil
    }

    private var activitySymbol: String {
        switch item.activityType {
        case .suggestionBurst:
            "checkmark.bubble.fill"
        case .consensusChanged:
            "arrow.triangle.2.circlepath"
        case .resolved:
            "checkmark.seal.fill"
        }
    }

    private var activityColor: Color {
        switch item.activityType {
        case .suggestionBurst:
            .blue
        case .consensusChanged:
            .orange
        case .resolved:
            .green
        }
    }

    private var relativeTimestamp: String {
        guard let date = item.activityDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct IdentifyActivityLoadingState: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    GlowPulsingSkeletonView(cornerRadius: 12, style: .raisedGrid)
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 8) {
                        GlowPulsingSkeletonView(cornerRadius: 5, style: .raisedGrid)
                            .frame(height: 14)
                        GlowPulsingSkeletonView(cornerRadius: 5, style: .raisedGrid)
                            .frame(width: 140, height: 11)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if index < count - 1 {
                    Divider()
                        .padding(.leading, 92)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .accessibilityLabel("Loading identification activity")
    }
}
