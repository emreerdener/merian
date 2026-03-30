import SwiftUI

struct SimilarSpeciesGallery: View {
    let similarData: SimilarSpecies
    let isLowConfidence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: - Header
            // HStack(spacing: 8) {
            //     Image(systemName: "square.grid.2x2")
            //         .foregroundColor(.secondary)
            //     Text("Similar species")
            //         .font(.system(.headline))
            //         .foregroundColor(.primary)
            // }

            // MARK: - Lookalike Target Carousel
            if !similarData.entries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isLowConfidence ? "POTENTIAL LOOKALIKES" : "SIMILAR SPECIES")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(similarData.entries, id: \.scientificName) { entry in
                                SimilarSpeciesCard(entry: entry, isLowConfidence: isLowConfidence)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 16) // Content inset matches title
                    }
                    .padding(.horizontal, -16) // Bleed parent padding
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Similar Species Card Component

struct SimilarSpeciesCard: View {
    let entry: SimilarSpeciesEntry
    let isLowConfidence: Bool

    // Fallback fetcher used only when the join table has no reference image URL.
    @StateObject private var imageFetcher = SimilarSpeciesImageFetcher()

    var body: some View {
        VStack(spacing: 0) {
            // Reference Image
            ZStack {
                Color(UIColor.systemGray6)

                if let remoteUrl = entry.referenceImageUrl {
                    // Rich path: reference image pre-resolved by the join table query.
                    AsyncLocalImageView(path: nil, fallbackImageUrl: remoteUrl)
                } else if imageFetcher.isLoading {
                    ProgressView()
                } else if let img = imageFetcher.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "leaf.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 120)
            .clipped()

            // Text Details & Confirmation Hook
            VStack(alignment: .leading, spacing: 4) {
                if let commonName = entry.commonName {
                    Text(commonName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(entry.scientificName)
                    .font(.caption)
                    .fontWeight(entry.commonName == nil ? .semibold : .regular)
                    .italic()
                    .foregroundColor(entry.commonName == nil ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLowConfidence {
                    Button(action: {
                        // Future hook: prompt user to override AI identity
                        HapticManager.shared.triggerLightImpact()
                    }) {
                        Text("Confirm Species")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                    }
                }
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemGroupedBackground))
        }
        .frame(width: 140)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .task(priority: .background) {
            // Fallback: lazy-load via Wikipedia/GBIF only when no reference URL was resolved.
            if entry.referenceImageUrl == nil {
                await imageFetcher.fetchImage(for: entry.scientificName)
            }
        }
    }
}

// MARK: - Skeleton Shimmer State
extension SimilarSpeciesGallery {
    struct Skeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Header
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .foregroundColor(.secondary)
                    Text("Similar Species")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("POTENTIAL LOOKALIKES")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .systemFill))
                                    .frame(width: 140, height: 180)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 16) // Content inset matches title
                    }
                    .padding(.horizontal, -16) // Bleed parent padding
                    .disabled(true)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .redacted(reason: .placeholder)
            .shimmering()
            .card()
        }
    }
}
