import SwiftUI

// MARK: - Review State

private enum ReviewState: Equatable {
    case pending
    case confirmed
    case overridden(to: String)
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

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @State private var isSwipeModalPresented = false

    private var reviewState: ReviewState {
        if let override = inferenceEngine.speciesData?.userIdentificationOverride {
            return .overridden(to: override)
        } else if inferenceEngine.speciesData?.userConfirmedIdentification == true {
            return .confirmed
        } else {
            return .pending
        }
    }

    var body: some View {
        Group {
            switch reviewState {
            case .confirmed:
                ConfirmedView(
                    aiScientificName: aiScientificName,
                    onReset: {
                        Task { await inferenceEngine.resetIdentificationReview(modelContext: modelContext) }
                    }
                )

            case .overridden(let overrideName):
                OverriddenView(
                    overrideName: overrideName,
                    aiScientificName: aiScientificName,
                    onUndo: {
                        Task { await inferenceEngine.resetIdentificationReview(modelContext: modelContext) }
                    }
                )

            case .pending:
                PendingView(
                    candidates: candidates,
                    onConfirm: {
                        Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                    },
                    onReviewAlternatives: { isSwipeModalPresented = true },
                    onFlagIssue: onFlagIssue
                )
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
    let onConfirm: () -> Void
    let onReviewAlternatives: () -> Void
    var onFlagIssue: (() -> Void)?

    var body: some View {
        if candidates.isEmpty {
            VStack(spacing: 32) {
                // Content Heading
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.bottom, 16)
                        
                    Text("Verify identification")
                        .font(.system(.title2).weight(.bold))
                        .foregroundColor(.primary)
                    Text("The model had low confidence on this match.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 16)
                
                // Action Buttons
                VStack(spacing: 12) {
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

                    Button {
                        onConfirm()
                    } label: {
                        Text("Confirm initial match")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        } else {
            VStack(spacing: 24) {
                // Content Heading
                VStack(spacing: 8) {
                    Text("Verify identification")
                        .font(.system(.title2).weight(.bold))
                        .foregroundColor(.primary)
                    Text("The model found \(candidates.count) close matches.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Visual Graphic stack
                ZStack {
                    ForEach(Array(candidates.prefix(3).enumerated().reversed()), id: \.offset) { index, candidate in
                        FlayedCandidateThumbnail(candidate: candidate)
                            .rotationEffect(.degrees(index == 1 ? 8 : (index == 2 ? -8 : 0)))
                            .offset(
                                x: index == 1 ? 24 : (index == 2 ? -24 : 0),
                                y: index == 0 ? 0 : 16
                            )
                            .zIndex(-Double(index))
                    }
                }
                .padding(.bottom, 24)
                   
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: onReviewAlternatives) {
                        Text("Review alternatives")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onConfirm) {
                        Text("Confirm initial match")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Flayed Thumbnail

private struct FlayedCandidateThumbnail: View {
    let candidate: IdentificationCandidate
    @StateObject private var imageFetcher = SimilarSpeciesImageFetcher()
    
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
            } else {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.quaternary)
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

// MARK: - Confirmed View (State 3)

private struct ConfirmedView: View {
    let aiScientificName: String
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
            Text("You confirmed this identification")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Button("Change", action: onReset)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Overridden View (State 4)

private struct OverriddenView: View {
    let overrideName: String
    let aiScientificName: String
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.checkmark")
                    .foregroundColor(.indigo)
                Text("Your identification")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
                Spacer()
                Button("Undo", action: onUndo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
            }

            Text(overrideName)
                .font(.system(.subheadline, design: .serif).italic())
                .foregroundColor(.primary)

            Text("AI originally suggested *\(aiScientificName)*")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
