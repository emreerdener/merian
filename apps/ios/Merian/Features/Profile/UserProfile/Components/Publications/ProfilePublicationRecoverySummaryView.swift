import SwiftUI

struct ProfilePublicationRecoverySummaryView: View {
    let summary: ProfilePublicationRecoverySummary
    let ownerUserID: String
    let onReview: () -> Void
    let onDismissFeedback: () -> Void

    @State private var locallyDismissedContext: String?

    var body: some View {
        if !isDismissed {
            HStack {
                Text(
                    "\(summary.recoveryNeededCount.formatted()) media unavailable"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

                Spacer()

                Button("Review scans", action: onReview)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .buttonStyle(.plain)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss unavailable media notice")
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var dismissalContext: String {
        ownerUserID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            + "|\(summary.overviewDismissalSignature)"
    }

    private var isDismissed: Bool {
        locallyDismissedContext == dismissalContext ||
            ProfileRecoveryNoticePreferences.dismissedSignature(
                ownerUserID: ownerUserID
            ) == summary.overviewDismissalSignature
    }

    private func dismiss() {
        onDismissFeedback()
        ProfileRecoveryNoticePreferences.dismiss(
            signature: summary.overviewDismissalSignature,
            ownerUserID: ownerUserID
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            locallyDismissedContext = dismissalContext
        }
    }
}
