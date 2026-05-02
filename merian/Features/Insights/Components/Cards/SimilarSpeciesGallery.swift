import SwiftUI

struct SimilarSpeciesGallery: View {
    let similarData: SimilarSpecies
    let currentScientificName: String?
    let currentCommonName: String?

    private var validEntries: [SimilarSpeciesEntry] {
        similarData.filteredEntries(
            excludingScientificName: currentScientificName,
            excludingCommonName: currentCommonName
        )
    }

    var body: some View {
        if !validEntries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "camera.filters")
                        .foregroundColor(.secondary)
                    Text("Similar species")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(validEntries, id: \.scientificName) { entry in
                            SimilarSpeciesCard(
                                entry: entry,
                                currentCommonName: currentCommonName
                            )
                        }
                    }
                    .padding(.bottom, 8) // Shadow clearance
                    .padding(.horizontal, 16) // Content inset matches title
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, -16) // Bleed parent padding
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Similar Species Card Component

struct SimilarSpeciesCard: View {
    let entry: SimilarSpeciesEntry
    let currentCommonName: String?

    // Fallback fetcher used only when the join table has no reference image URL.
    @State private var imageFetcher = SimilarSpeciesImageFetcher()
    @State private var remoteImageFailed = false

    private var displayCommonName: String? {
        entry.displayCommonName(comparedTo: currentCommonName)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background Image
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
                } else if let img = imageFetcher.images.first {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "leaf.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 200, height: 260)
            .clipped()

            // Text Details Overlay
            VStack(alignment: .leading, spacing: 2) {
                if let commonName = displayCommonName {
                    Text(commonName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(entry.scientificName)
                    .font(.caption)
                    .fontWeight(displayCommonName == nil ? .semibold : .regular)
                    .italic()
                    .foregroundColor(displayCommonName == nil ? .primary : .secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.0), .white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
            .padding(10)
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
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "camera.filters")
                        .foregroundColor(.secondary)
                    Text("Similar species")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonCard()
                        }
                    }
                    .padding(.bottom, 12) // Shadow clearance
                    .padding(.horizontal, 16) // Content inset matches title
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, -16) // Bleed parent padding
                .disabled(true)
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
            ZStack(alignment: .bottom) {
                // Background Image Placeholder
                Color(uiColor: .systemFill)
                    .frame(width: 200, height: 260)
                    .clipped()
                
                // Text Placeholder Overlay
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 100, height: 16)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 140, height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.0), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
                .padding(10)
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
