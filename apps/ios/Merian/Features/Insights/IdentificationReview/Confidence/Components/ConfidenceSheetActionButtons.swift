import SwiftUI

struct ConfidenceSheetActionButtons: View {
    let isReanalyzeLocked: Bool
    var onReanalyze: (() -> Void)?
    var onAskCommunity: (() -> Void)?
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
        }
        .frame(maxWidth: .infinity)
    }
}
