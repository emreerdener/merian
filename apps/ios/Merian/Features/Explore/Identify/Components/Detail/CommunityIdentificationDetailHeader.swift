import SwiftUI

struct CommunityIdentificationDetailHero: View {
    let detail: CommunityIdentificationDetail

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = max(width, 320)
            let bleedBuffer: CGFloat = 48

            ExplorePublicMediaView(
                mediaItem: detail.resolvedMediaItems.first ?? .legacyImage(url: detail.heroImageUrl),
                fallbackImageUrl: detail.heroImageUrl,
                reloadGeneration: 0,
                preloadedImage: nil,
                surface: .communityIdentification,
                autoplay: true,
                showsVideoControls: true
            )
            .frame(width: width, height: height + bleedBuffer)
            .offset(y: -bleedBuffer)
            .clipped()
        }
        .frame(height: max(UIScreen.main.bounds.width, 320))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.black.opacity(0.36), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 132)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}

struct CommunityAIIdentificationCard: View {
    let detail: CommunityIdentificationDetail

    @Environment(\.colorScheme) private var colorScheme
    @State private var isReasoningExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Label(modelLabel, systemImage: "sparkle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                Spacer(minLength: 12)

                if let confidenceLabel {
                    Text(confidenceLabel)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(aiDisplayName)
                    .font(.title3)
                    .fontWeight(.bold)

                if let aiScientificName {
                    Text(aiScientificName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let aiReasoning {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isReasoningExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("AI reasoning")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(isReasoningExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isReasoningExpanded ? "Hide AI reasoning" : "Show AI reasoning")

                if isReasoningExpanded {
                    Text(aiReasoning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(16)
        .background(
            colorScheme == .light
                ? Color(red: 0.95, green: 0.96, blue: 0.98)
                : Color(uiColor: .secondarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var aiSuggestion: CommunityTaxonSearchResult? {
        detail.suggestedTaxa?.first { $0.suggestionSource == .aiInitial }
    }

    private var aiDisplayName: String {
        aiSuggestion?.displayName
            ?? CommunityTaxonDisplay.name(
                commonName: detail.initialCommonName,
                scientificName: detail.initialScientificName
            )
    }

    private var aiScientificName: String? {
        let value = aiSuggestion?.scientificName ?? detail.initialScientificName
        guard let scientificName = trimmed(value) else { return nil }
        guard scientificName.localizedCaseInsensitiveCompare(aiDisplayName) != .orderedSame else {
            return nil
        }
        return scientificName
    }

    private var confidenceLabel: String? {
        guard let score = aiSuggestion?.confidenceScore else { return nil }
        let clampedScore = min(max(score, 0), 1)
        return "\(Int((clampedScore * 100).rounded()))% confident"
    }

    private var aiReasoning: String? {
        trimmed(aiSuggestion?.distinguishingFeature)
    }

    private var modelLabel: String {
        switch detail.inferenceTier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pro":
            "Naturebook Pro"
        default:
            "Naturebook Flash"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let result = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            return nil
        }
        return result
    }
}
