import SwiftUI

// MARK: - Review State

private enum ReviewState: Equatable {
    case pending
    case confirmed
    case overridden(to: String)
    case flagged
}

// MARK: - Candidates Card

/// Surfaces the AI's alternative identification candidates and collects a one-time
/// user review (Was the AI correct? / Not sure → opens swipe modal).
struct CandidatesCard: View {
    let candidates: [IdentificationCandidate]
    /// The AI's original scientific name — shown in the "overridden" state as "AI suggested X".
    let aiScientificName: String
    let inferenceTier: String?
    /// Called when the user taps "No, incorrect" and there are no candidates to choose from.
    /// The caller should route to the flag/report flow.
    var onFlagIssue: (() -> Void)?
    var onMatchConfirmed: (() -> Void)?
    var showDismissButton: Bool = true

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @State private var isSwipeModalPresented = false
    @State private var dismissedScanId: String?

    private var reviewState: ReviewState {
        if inferenceEngine.speciesData?.isFlagged == true {
            return .flagged
        } else if let override = inferenceEngine.speciesData?.userIdentificationOverride {
            return .overridden(to: override)
        } else if inferenceEngine.speciesData?.userConfirmedIdentification == true {
            return .confirmed
        } else {
            return .pending
        }
    }

    private var displayCommonName: String {
        let name = inferenceEngine.speciesData?.commonName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? aiScientificName : name.capitalized
    }

    var body: some View {
        Group {
            switch reviewState {
            case .confirmed:
                EmptyView()

            case .overridden:
                EmptyView()

            case .flagged:
                EmptyView()

            case .pending:
                if let scanId = inferenceEngine.speciesData?.scanId, dismissedScanId == scanId {
                    EmptyView()
                } else {
                    PendingView(
                        candidates: candidates,
                        aiCommonName: displayCommonName,
                        onConfirm: {
                            HapticManager.shared.triggerSuccessPulse()
                            onMatchConfirmed?()
                            Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                        },
                        onReviewAlternatives: { isSwipeModalPresented = true },
                        onFlagIssue: onFlagIssue,
                        onDismiss: { dismissedScanId = inferenceEngine.speciesData?.scanId },
                        showDismissButton: showDismissButton
                    )
                }
            }
        }
        .sheet(isPresented: $isSwipeModalPresented) {
            CandidateSwipeModal(
                candidates: candidates,
                aiScientificName: aiScientificName,
                onFlagIssue: onFlagIssue
            )
        }
    }
}

// MARK: - Pending View

private struct PendingView: View {
    let candidates: [IdentificationCandidate]
    let aiCommonName: String
    let onConfirm: () -> Void
    let onReviewAlternatives: () -> Void
    var onFlagIssue: (() -> Void)?
    let onDismiss: () -> Void
    var showDismissButton: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if candidates.isEmpty {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 32) {
                    // Content Heading
                    VStack(spacing: 8) {                        
                        Text("Verify identification")
                            .font(.system(.title2).weight(.bold))
                            .foregroundColor(.primary)
                        Text("The model had low confidence on this match")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                         Button {
                            onConfirm()
                        } label: {
                            Text("Confirm match")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                         Button {
                            onFlagIssue?()
                        } label: {
                            Text("Flag as incorrect")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if showDismissButton {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        } else {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: candidates.count > 1 ? 48 : 24) {
                // Visual Graphic stack
                ZStack {
                    let displayCandidates = Array(candidates.prefix(2))
                    let isPair = displayCandidates.count == 2
                    
                    ForEach(Array(displayCandidates.enumerated().reversed()), id: \.offset) { index, candidate in
                        let rotation: Double = isPair ? (index == 0 ? -5 : 5) : .zero
                        let offsetX: CGFloat = isPair ? (index == 0 ? -16 : 16) : .zero
                        let offsetY: CGFloat = isPair ? (index == 0 ? 0 : 12) : .zero

                        FlayedCandidateThumbnail(candidate: candidate)
                            .rotationEffect(.degrees(rotation))
                            .offset(x: offsetX, y: offsetY)
                            .zIndex(-Double(index))
                            .visualEffect { content, proxy in
                                let scrollOffset = proxy.frame(in: .global).minY
                                let wave = sin(scrollOffset / 200.0)
                                
                                // Subtle fan out effect from the bottom center
                                let rotationWiggle = Double(wave) * (index == 0 ? -3.0 : 3.0)
                                
                                return content
                                    .rotationEffect(.degrees(rotationWiggle), anchor: .bottom)
                            }
                    }
                }
                .padding(.top, 8)
                .onTapGesture(perform: onReviewAlternatives)

                VStack(spacing: 24) {
                    // Content Heading
                    VStack(spacing: 8) {
                        Text("\(candidates.count) close \(candidates.count == 1 ? "match" : "matches") found")
                            .font(.system(.title2).weight(.bold))
                            .foregroundColor(.primary)
                        Text("Other species the model also considered")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: onReviewAlternatives) {
                            Text("Review alternatives")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    ZStack {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                        Capsule()
                                            .fill(Color.green.opacity(0.75))
                                    }
                                )
                                .foregroundColor(.white)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                                        .blendMode(.overlay)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } // Close VStack(spacing: candidates.count > 1 ? 48 : 24)

            if showDismissButton {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Flayed Thumbnail
private struct FlayedCandidateThumbnail: View {
    let candidate: IdentificationCandidate
    @State private var imageFetcher = SimilarSpeciesImageFetcher()
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            
            if let img = imageFetcher.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if imageFetcher.isLoading {
                ProgressView()
                    .tint(.secondary)
            } else {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 32))
            }
        }
        .frame(width: 164, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .task { _ = await imageFetcher.fetchImage(for: candidate.scientificName) }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Pending State - Single") {
    CandidatesCard(
        candidates: [
            IdentificationCandidate(scientificName: "Limenitis archippus", commonName: "Viceroy", confidenceScore: 0.71)
        ],
        aiScientificName: "Danaus plexippus",
        inferenceTier: "flash"
    )
    .environment(InferenceEngine())
    .padding()
}

#Preview("Pending State - Pair") {
    CandidatesCard(
        candidates: [
            IdentificationCandidate(scientificName: "Limenitis archippus", commonName: "Viceroy", confidenceScore: 0.71),
            IdentificationCandidate(scientificName: "Danaus gilippus", commonName: "Queen", confidenceScore: 0.58)
        ],
        aiScientificName: "Danaus plexippus",
        inferenceTier: "flash"
    )
    .environment(InferenceEngine())
    .padding()
}
#endif
