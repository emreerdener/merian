import SwiftUI

struct QueuedRetryStatusView: View {
    let presentation: QueuedRetryPresentation
    let isRetrying: Bool
    let onRetry: () -> Void
    let onViewPlans: () -> Void
    let onReviewOpenAIPermission: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(presentation.message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let action = presentation.action {
                Button {
                    switch action {
                    case .retryNow:
                        onRetry()
                    case .viewPlans:
                        onViewPlans()
                    case .reviewOpenAIPermission:
                        onReviewOpenAIPermission()
                    }
                } label: {
                    switch action {
                    case .retryNow:
                        Label(
                            isRetrying ? "Retrying..." : "Retry now",
                            systemImage: "arrow.clockwise"
                        )
                    case .viewPlans:
                        Label("View plans", systemImage: "sparkles")
                    case .reviewOpenAIPermission:
                        Label("Review permission", systemImage: "hand.raised")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(action == .retryNow && isRetrying)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 8)
    }
}
