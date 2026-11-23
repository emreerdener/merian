import SwiftUI

/// Existing prepared routes, presented beneath a rejected identification.
struct IdentificationRecoveryActions: View {
    var communityTitle = "Ask the community"
    var reanalysisTitle = "Reanalyze species"
    var onCommunity: (() -> Void)?
    var onReanalysis: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            if let onCommunity {
                action(communityTitle, color: .blue, identifier: "IdentificationCommunityAction", perform: onCommunity)
            }
            if let onReanalysis {
                action(reanalysisTitle, color: .orange, identifier: "IdentificationReanalysisAction", perform: onReanalysis)
            }
        }
    }

    private func action(_ title: String, color: Color, identifier: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right").font(.headline)
                    .foregroundStyle(.white).frame(width: 40, height: 40)
                    .background(color, in: Circle())
                Text(title).font(.headline).frame(maxWidth: .infinity)
                Color.clear.frame(width: 40, height: 40).accessibilityHidden(true)
            }
            .foregroundStyle(color).padding(8)
            .background(color.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
}

/// Presentation only; the sheet supplies identity-fenced review and recovery actions.
struct IdentificationReviewBanner: View {
    let review: LocalAIIdentificationReview?
    let isConfirmed: Bool
    var onUndoIncorrect: (() -> Void)?
    var onConfirmProposal: (() -> Void)?
    var unavailableReason: String?
    var confirmationUndoReason: String?
    var onResetConfirmation: (() -> Void)?
    let communityTitle: String
    let reanalysisTitle: String
    var onCommunity: (() -> Void)?
    var onReanalysis: (() -> Void)?

    var body: some View {
        if let review, review.isUnresolved || review.needsAttention {
            IncorrectIdentificationView(
                review: review, onUndo: onUndoIncorrect, onConfirm: onConfirmProposal,
                unavailableReason: onUndoIncorrect == nil
                    ? unavailableReason ?? IdentificationReviewNotice.unavailableReason(review) : nil)
            if review.state == .aiRejected && !review.needsAttention {
                IdentificationRecoveryActions(communityTitle: communityTitle, reanalysisTitle: reanalysisTitle,
                    onCommunity: onCommunity, onReanalysis: onReanalysis)
            }
        } else if isConfirmed {
            ConfirmedView(onReset: onResetConfirmation, unavailableReason: confirmationUndoReason)
        }
    }
}

struct ConfidenceSheetActionButtons: View {
    let isReanalyzeLocked: Bool
    var onReanalyze: (() -> Void)?
    var onAskCommunity: (() -> Void)?
    var onMarkIncorrect: (() -> Void)?
    let feedback: IdentificationReviewFeedbackDependencies

    var body: some View {
        VStack(spacing: 12) {
            if let onReanalyze {
                Button(action: onReanalyze) {
                    Label(
                        "Reanalyze species",
                        systemImage: isReanalyzeLocked
                            ? "lock.fill"
                            : "arrow.2.circlepath"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange.opacity(0.14))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfidenceSheetReanalyzeButton")
            }

            if let onAskCommunity {
                Button {
                    feedback.mediumPulse()
                    onAskCommunity()
                } label: {
                    Label("Ask the community", systemImage: "person.2")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue.opacity(0.14))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfidenceSheetAskCommunityButton")
            }
            if let onMarkIncorrect {
                Button(role: .destructive, action: onMarkIncorrect) {
                    Label("Mark as incorrect", systemImage: "xmark.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.14))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ConfidenceSheetMarkIncorrectButton")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
