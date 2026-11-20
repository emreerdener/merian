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
            ViewThatFits(in: .horizontal) {
                HStack {
                    noticeText.fixedSize()
                    Spacer()
                    actions.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    noticeText
                    actions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var noticeText: some View {
        Text("\(summary.recoveryNeededCount.formatted()) media unavailable")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack {
            Button("Review scans", action: onReview)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)

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
