import SwiftUI

/// Distinguishes an explicit rejection from a replacement awaiting acceptance.
struct IncorrectIdentificationView: View {
    var review: LocalAIIdentificationReview
    var onUndo: (() -> Void)?
    var onConfirm: (() -> Void)?
    var unavailableReason: String?

    private var color: Color { review.state == .aiRejected && !review.needsAttention ? .red : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: review.state == .aiRejected ? "xmark.circle.fill" : "questionmark.circle")
                    .foregroundColor(color)
                Text(IdentificationReviewNotice.title(review))
                    .font(.system(.headline))
                    .foregroundColor(color)
                Spacer()
                if let onUndo {
                    Button("Undo", action: onUndo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(color)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("IncorrectIdentificationUndoButton")
                }
            }

            Text(IdentificationReviewNotice.explanation(review))
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let onConfirm {
                Button("Accept this identification", action: onConfirm)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("ReanalysisProposalConfirmButton")
            }
            if let unavailableReason {
                Text(unavailableReason).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
        )
    }
}
