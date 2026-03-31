import SwiftUI

// MARK: - Swipeable Candidate Card
struct SwipeableCandidateCard: View {
    let candidate: IdentificationCandidate
    let isDragging: Bool
    let dragPercentage: Double
    let isSwipingRight: Bool
    let isSwipingLeft: Bool

    // NOTE: Uses SimilarSpeciesImageFetcher — dual-source Wikipedia/GBIF async image loading
    // with in-memory NSCache. See Features/Insights/Utilities/SimilarSpeciesImageFetcher.swift
    @State private var imageFetcher = SimilarSpeciesImageFetcher()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Base card
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            // Species image — async loaded via Wikipedia then GBIF fallback
            if let img = imageFetcher.image {
                Color.clear
                    .overlay(
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if imageFetcher.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "leaf.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(.quaternary)
                    Text("Image unavailable")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Colour overlays — scale with drag progress
            if isSwipingRight {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.green.opacity(dragPercentage * 0.38))
            }
            if isSwipingLeft {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.red.opacity(dragPercentage * 0.38))
            }

            // Confirm indicator — top-left, shown on right swipe
            if isSwipingRight {
                VStack {
                    HStack {
                        CandidateSwipeIndicator(label: "Confirm", iconName: "checkmark", color: .green, progress: dragPercentage)
                            .padding([.top, .leading], 18)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Reject indicator — top-right, shown on left swipe
            if isSwipingLeft {
                VStack {
                    HStack {
                        Spacer()
                        CandidateSwipeIndicator(label: "Reject", iconName: "xmark", color: .red, progress: dragPercentage)
                            .padding([.top, .trailing], 18)
                    }
                    Spacer()
                }
            }

            // Species info bottom bar
            VStack(alignment: .leading, spacing: 8) {
                // Confidence score
                Text("\(Int(candidate.confidenceScore * 100))% match")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    )

                // Common name and scientific name
                if let common = candidate.commonName, !common.isEmpty {
                    Text(common.capitalized)
                        .font(.system(.title, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(candidate.scientificName)
                        .font(.subheadline.italic())
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    // Only scientific name
                    Text(candidate.scientificName)
                        .font(.system(.title, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .padding(.top, 64)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .task { _ = await imageFetcher.fetchImage(for: candidate.scientificName) }
    }
}
