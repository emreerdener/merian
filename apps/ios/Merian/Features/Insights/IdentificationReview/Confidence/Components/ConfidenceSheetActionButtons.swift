import SwiftUI

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
