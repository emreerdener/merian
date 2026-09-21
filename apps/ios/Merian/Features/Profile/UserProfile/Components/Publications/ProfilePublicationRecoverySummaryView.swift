import SwiftUI

struct ProfilePublicationRecoverySummaryView: View {
    let summary: ProfilePublicationRecoverySummary
    let ownerUserID: String
    let onReview: () -> Void
    let onDismissFeedback: () -> Void

    @AppStorage private var dismissedSignature: String?

    init(
        summary: ProfilePublicationRecoverySummary,
        ownerUserID: String,
        onReview: @escaping () -> Void,
        onDismissFeedback: @escaping () -> Void
    ) {
        self.summary = summary
        self.ownerUserID = ownerUserID
        self.onReview = onReview
        self.onDismissFeedback = onDismissFeedback
        _dismissedSignature = AppStorage(
            ProfileRecoveryNoticePreferences.preferenceKey(ownerUserID: ownerUserID)
        )
    }

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

    private var isDismissed: Bool {
        ProfileRecoveryNoticePreferences.isDismissed(
            summary: summary,
            signature: dismissedSignature
        )
    }

    private func dismiss() {
        onDismissFeedback()
        withAnimation(.easeInOut(duration: 0.2)) {
            dismissedSignature = summary.overviewDismissalSignature
        }
    }
}
