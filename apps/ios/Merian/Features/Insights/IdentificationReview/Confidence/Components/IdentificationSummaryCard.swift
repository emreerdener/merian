import SwiftUI

struct IdentificationSheetActions {
    var onHistory: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    var onReanalysisStatus: (() -> Void)?
    var onConfirmIdentification: (() -> Void)?
    var onMarkIdentificationIncorrect: (() -> Void)?
    var onRetryReview: (() -> Void)?
    var summaryImagePath: String?
    var summaryDate: Date?
}

/// Render-only summary; review persistence remains with the existing host.
struct IdentificationSummaryCard<ReviewContent: View>: View {
    let presentation: ConfidenceBadgePresentation
    let species: SpeciesData?
    let summaryImagePath: String?
    let summaryDate: Date?
    let feedback: IdentificationReviewFeedbackDependencies
    let isCurrent: () -> Bool
    var onConfirmIdentification: (() -> Void)?
    var onMarkIdentificationIncorrect: (() -> Void)?
    var onRetryReview: (() -> Void)?
    @ViewBuilder var reviewContent: () -> ReviewContent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                CurrentIdentificationBadge()
                ConfidenceStatusBadge(label: presentation.label, style: presentation.style)
            }
            HStack(spacing: 12) {
                ScanThumbnail(isOnline: true, imagePath: summaryImagePath, maxDimension: 160)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if let summaryDate {
                        Text(summaryDate, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(species?.commonName ?? "Identification").font(.headline)
                    if let name = species?.scientificName {
                        Text(name).font(.subheadline).italic().foregroundStyle(.secondary)
                    }
                }
            }
            reviewContent()
            if let onConfirmIdentification {
                SlideToConfirm(label: "Confirm identification", onConfirm: {
                    guard isCurrent() else { return }
                    onConfirmIdentification()
                }, feedback: feedback)
                .accessibilityIdentifier("IdentificationConfirm")
            }
            if let onMarkIdentificationIncorrect {
                SlideToConfirm(label: "Mark as incorrect", onConfirm: {
                    guard isCurrent() else { return }
                    onMarkIdentificationIncorrect()
                }, feedback: feedback, color: .red)
                .accessibilityIdentifier("IdentificationIncorrect")
            }
            if let onRetryReview { Button("Retry saving review", action: onRetryReview) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, 16)
    }
}

struct IdentificationSheetToolbar: ToolbarContent {
    let onClose: () -> Void
    var onHistory: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    var communityRequestAction: (() -> Void)?
    var onReanalysisStatus: (() -> Void)?
    var refinementAction: (() -> Void)?

    private var historySymbol: String {
        if #available(iOS 26.0, *) { return "sparkle.text.clipboard" }
        return "list.clipboard"
    }

    var body: some ToolbarContent {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") { onClose() }
                    .accessibilityIdentifier("IdentificationClose")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let onHistory {
                        Button("Identification history", systemImage: historySymbol, action: onHistory)
                            .accessibilityIdentifier("IdentificationHistoryMenu")
                        Divider()
                    }
                    if let onViewCommunityRequest {
                        Button("View community request", systemImage: "person.2", action: onViewCommunityRequest)
                    } else if let communityRequestAction {
                        Button("Ask the community", systemImage: "person.2", action: communityRequestAction)
                    }
                    if let onReanalysisStatus {
                        Button("View reanalysis progress", systemImage: "clock", action: onReanalysisStatus)
                    }
                    if let refinementAction {
                        Button("Reanalyze species", systemImage: "arrow.2.circlepath", action: refinementAction)
                            .accessibilityIdentifier("ReanalyzeSpeciesMenu")
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.primary) }
                .tint(Color(uiColor: .label))
                .accessibilityLabel("Identification actions")
                .accessibilityIdentifier("IdentificationActionsMenu")
            }
    }
}
