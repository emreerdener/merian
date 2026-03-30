import SwiftUI

struct SimilarSpeciesGallery: View {
    let similarData: SimilarSpecies

    private var validEntries: [SimilarSpeciesEntry] {
        similarData.entries
            .filter { !$0.scientificName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        if !validEntries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Lookalike Target Carousel
                VStack(alignment: .leading, spacing: 12) {
                    Text("SIMILAR SPECIES")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(validEntries, id: \.scientificName) { entry in
                                SimilarSpeciesCard(entry: entry)
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

    // Fallback fetcher used only when the join table has no reference image URL.
    @StateObject private var imageFetcher = SimilarSpeciesImageFetcher()
    @State private var remoteImageFailed = false

    var body: some View {
        VStack(spacing: 0) {
            // Reference Image
            ZStack {
                Color(UIColor.systemGray6)

                if !remoteImageFailed, let remoteUrl = entry.referenceImageUrl {
                    // Rich path: reference image pre-resolved by the join table query.
                    AsyncLocalImageView(
                        path: nil,
                        fallbackImageUrl: remoteUrl,
                        onImageLoadFailed: { remoteImageFailed = true }
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
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()

            // Text Details & Confirmation Hook
            VStack(alignment: .leading, spacing: 4) {
                if let commonName = entry.commonName {
                    Text(commonName)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(entry.scientificName)
                    .font(.caption)
                    .fontWeight(entry.commonName == nil ? .semibold : .regular)
                    .italic()
                    .foregroundColor(entry.commonName == nil ? .primary : .secondary)                    
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 80, alignment: .topLeading)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemGroupedBackground))
        }
        .frame(width: 200, height: 260)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .task(priority: .background) {
            // Fallback: lazy-load via Wikipedia/GBIF only when no reference URL was resolved.
            if entry.referenceImageUrl == nil {
                _ = await imageFetcher.fetchImage(for: entry.scientificName)
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
                    Text("SIMILAR SPECIES")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                
                // Text Placeholder Details
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 100, height: 16)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 140, height: 16)
                }
                .frame(height: 80, alignment: .topLeading)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            .frame(width: 200, height: 260)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }
}
