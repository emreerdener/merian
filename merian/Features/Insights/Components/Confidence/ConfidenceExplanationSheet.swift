import CoreLocation
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?

    @Environment(EnvironmentContextManager.self) private var environmentContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @State private var isReportPresented = false
    @State private var showPaywall = false

    private var showLocationPrompt: Bool {
        let status = environmentContext.locationAuthorizationStatus
        return status == .notDetermined || status == .restricted || status == .denied
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                ConfidenceHeader()

                ModelTierBadge(
                    confidenceScore: confidenceScore,
                    inferenceTier: inferenceTier
                )
                
                let candidates = inferenceEngine.speciesData?.candidates ?? []
                if isFlagged && candidates.count >= 2 {
                    AllCandidatesReviewedView(
                        candidates: candidates,
                        aiScientificName: aiScientificName ?? "Unknown",
                        onReset: {
                            Task { await inferenceEngine.resetIdentificationReview(modelContext: modelContext) }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if isFlagged {
                    UnderReviewView(
                        onUndo: {
                            Task { await inferenceEngine.unflagAIIdentification(modelContext: modelContext) }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if let override = userIdentificationOverride {
                    OverriddenView(
                        overrideName: override,
                        aiScientificName: aiScientificName ?? "Unknown",
                        onUndo: {
                            Task {
                                await inferenceEngine.resetIdentificationReview(modelContext: modelContext)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if userConfirmedIdentification {
                    ConfirmedView(
                        onReset: {
                            Task {
                                await inferenceEngine.resetIdentificationReview(modelContext: modelContext)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else {
                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: aiScientificName ?? "Unknown subject",
                        inferenceTier: inferenceTier,
                        onFlagIssue: {
                            isReportPresented = true
                        },
                        onMatchConfirmed: nil,
                        showDismissButton: false
                    )
                    .padding(.horizontal, 16)
                }

                PlanCard(showPaywall: $showPaywall)
                    .padding(.horizontal, 16)

                ConfidenceSpectrum(inferenceTier: inferenceTier)
                
                ProTips(showLocationPrompt: showLocationPrompt)
            }
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .sheet(isPresented: $isReportPresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                ReportInsightView(scanId: scanId)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

// MARK: - Confirmed View (State 3)

private struct ConfirmedView: View {
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("You confirmed this identification")
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Button("Undo", action: onReset)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
        }
        .card()
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
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .card()
    }
}

// MARK: - All Candidates Reviewed View (State 5a — swipe path)

/// Shown in ConfidenceExplanationSheet when the user reviewed all swipe-deck alternatives
/// and rejected each one. Replaces CandidatesCard in BiologicalView for this state.
private struct AllCandidatesReviewedView: View {
    let candidates: [IdentificationCandidate]
    let aiScientificName: String
    let onReset: () -> Void
    @State private var isSwipeModalPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.minus")
                    .foregroundColor(.secondary)
                Text("Alternatives reviewed")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
                Spacer()
                Button("Reset", action: onReset)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
            }

            Text("You reviewed all \(candidates.count) alternative\(candidates.count == 1 ? "" : "s") and none matched.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isSwipeModalPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.circlepath")
                    Text("Review again")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1))
                .foregroundColor(.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .card()
        .sheet(isPresented: $isSwipeModalPresented) {
            CandidateSwipeModal(
                candidates: candidates,
                aiScientificName: aiScientificName,
                onFlagIssue: nil
            )
        }
    }
}

// MARK: - Under Review View (State 5b — no-candidates flag path)

private struct UnderReviewView: View {
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
                Text("Flagged for review")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
                Spacer()
                Button("Undo", action: onUndo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
            }

            Text("This identification has been flagged because it was incorrect. It will be verified by a moderator soon.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
}
