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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                Text("Was the AI correct?")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
            }

            if candidates.isEmpty {
                Text("The AI had below-average confidence on this identification.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("The model considered \(candidates.count) alternative\(candidates.count == 1 ? "" : "s"). Tap to review.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    onConfirm()
                } label: {
                    Label("Yes, correct", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if candidates.isEmpty {
                    // No alternatives — route straight to the flag/report flow.
                    Button {
                        onFlagIssue?()
                    } label: {
                        Label("No, incorrect", systemImage: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        onReviewAlternatives()
                    } label: {
                        Label("Not sure", systemImage: "questionmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
