import SwiftUI

struct SimilarSpeciesGallery: View {
    let similarData: SimilarSpecies
    let isLowConfidence: Bool
    
    @State private var failedMediaIdentifiers = Set<String>()

    private var validEntries: [SimilarSpeciesEntry] {
        similarData.entries
            .filter { !$0.scientificName.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { !failedMediaIdentifiers.contains($0.scientificName) }
    }

    var body: some View {
        if !validEntries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Lookalike Target Carousel
                VStack(alignment: .leading, spacing: 12) {
                    Text(isLowConfidence ? "POTENTIAL LOOKALIKES" : "SIMILAR SPECIES")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(validEntries, id: \.scientificName) { entry in
                                SimilarSpeciesCard(
                                    entry: entry,
                                    isLowConfidence: isLowConfidence,
                                    onImageFailed: {
                                        withAnimation(.easeInOut) {
                                            _ = failedMediaIdentifiers.insert(entry.scientificName)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 16) // Content inset matches title
                    }
                    .padding(.horizontal, -16) // Bleed parent padding
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Similar Species Card Component

struct SimilarSpeciesCard: View {
    let entry: SimilarSpeciesEntry
    let isLowConfidence: Bool
    let onImageFailed: () -> Void

    // Fallback fetcher used only when the join table has no reference image URL.
    @StateObject private var imageFetcher = SimilarSpeciesImageFetcher()

    var body: some View {
        VStack(spacing: 0) {
            // Reference Image
            ZStack {
                Color(UIColor.systemGray6)

                if let remoteUrl = entry.referenceImageUrl {
                    // Rich path: reference image pre-resolved by the join table query.
                    AsyncLocalImageView(
                        path: nil,
                        fallbackImageUrl: remoteUrl,
                        onImageLoadFailed: onImageFailed
                    )
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Text Details & Confirmation Hook
            VStack(alignment: .leading, spacing: 4) {
                if let commonName = entry.commonName {
                    Text(commonName)
                        .font(.subheadline)
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

                // TODO: Add confirmation hook
                // if isLowConfidence {
                //     Button(action: {
                //         // Future hook: prompt user to override AI identity
                //         HapticManager.shared.triggerLightImpact()
                //     }) {
                //         Text("Confirm Species")
                //             .font(.system(size: 11, weight: .bold))
                //             .foregroundColor(.white)
                //             .padding(.vertical, 6)
                //             .frame(maxWidth: .infinity)
                //             .background(Color.accentColor)
                //             .cornerRadius(6)
                //     }
                // }
            }
            .frame(height: 48, alignment: .topLeading)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemGroupedBackground))
        }
        .frame(width: 180, height: 240)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .task(priority: .background) {
            // Fallback: lazy-load via Wikipedia/GBIF only when no reference URL was resolved.
            if entry.referenceImageUrl == nil {
                let success = await imageFetcher.fetchImage(for: entry.scientificName)
                if !success {
                    onImageFailed()
                }
            }
        }
    }
}

// MARK: - Skeleton Shimmer State
extension SimilarSpeciesGallery {
    struct Skeleton: View {
        @State private var isPulsing = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("POTENTIAL LOOKALIKES")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonCard()
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
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }

    struct SkeletonCard: View {
        var body: some View {
            VStack(spacing: 0) {
                // Image Placeholder
                Color(uiColor: .systemFill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Text Placeholder Details
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 100, height: 16)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 140, height: 16)
                }
                .frame(height: 48, alignment: .topLeading)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            .frame(width: 180, height: 240)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }
}
