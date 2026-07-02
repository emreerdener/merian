import SwiftUI

// MARK: - Swipeable Candidate Card
struct SwipeableCandidateCard: View {
    let candidate: IdentificationCandidate
    let isDragging: Bool
    let dragPercentage: Double
    let isSwipingRight: Bool
    let isSwipingLeft: Bool

    // NOTE: Uses SimilarSpeciesImageFetcher — dual-source Wikipedia/GBIF async image loading
    // with in-memory NSCache. See Features/Insights/SpeciesReference/Utilities/SimilarSpeciesImageFetcher.swift
    @State private var imageFetcher = SimilarSpeciesImageFetcher()
    @State private var isOriginalImageExpanded = false
    @State private var isCandidateImageExpanded = false
    @State private var candidateSelectedImage: UIImage?
    @State private var isFeatureExpanded = false
    @Environment(InferenceEngine.self) private var inferenceEngine

    private var hasAdditionalCandidateImages: Bool {
        imageFetcher.images.count > 1
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Base card
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            // Species image — async loaded via Wikipedia then GBIF fallback
            if let img = imageFetcher.images.first {
                Color.clear
                    .overlay(
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isCandidateImageExpanded = true
                    }
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

            if hasAdditionalCandidateImages && !isSwipingLeft {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                            .padding([.top, .trailing], 18)
                            .accessibilityHidden(true)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Bottom gradient — sits above the image/overlays but below the text and PIP Picture in Picture.
            // Inserted here in ZStack source order so no explicit zIndex manipulation is needed.
            VStack {
                Spacer()
                Color.clear
                    .frame(height: 200)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6), .black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
                    )
                    .allowsHitTesting(false)
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
                let _common = (imageFetcher.commonName ?? candidate.commonName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !_common.isEmpty && _common.lowercased() != candidate.scientificName.lowercased() {
                    Text(_common.capitalized)
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
                // Distinguishing feature — the one observable trait that separates
                // this candidate from the primary identification.
                if let feature = candidate.distinguishingFeature, !feature.isEmpty {
                    let sentenceCased = feature.prefix(1).uppercased() + feature.dropFirst()
                    Text(sentenceCased)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                        .padding(.top, 1)
                        .onTapGesture { isFeatureExpanded = true }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)
            .padding(.trailing, 96) // Clear the PiP (58 width + 20 margin + 18 gap)
            .padding(.bottom, 20)
            
            // Original Image PIP (Bottom Right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        isOriginalImageExpanded = true
                    } label: {
                        OriginalCapturePiPView()
                            .frame(width: 58, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            .contentShape(Rectangle()) // Ensures tap registers on whole frame
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .task { _ = await imageFetcher.fetchImage(for: candidate.scientificName) }
        .sheet(isPresented: $isOriginalImageExpanded) {
            OriginalCaptureExpandedView()
                .environment(inferenceEngine)
                .presentationDragIndicator(.visible)
                .presentationDetents([.fraction(0.85), .large])
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $isCandidateImageExpanded) {
            if !imageFetcher.images.isEmpty {
                CandidateImageExpandedView(images: imageFetcher.images, selectedImage: $candidateSelectedImage)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.fraction(0.85), .large])
                    .presentationCornerRadius(32)
            }
        }
        .sheet(isPresented: $isFeatureExpanded) {
            if let feature = candidate.distinguishingFeature, !feature.isEmpty {
                let sentenceCased = feature.prefix(1).uppercased() + feature.dropFirst()
                DistinguishingFeatureSheetView(feature: String(sentenceCased))
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.fraction(0.35)])
                    .presentationCornerRadius(32)
            }
        }
    }
}
