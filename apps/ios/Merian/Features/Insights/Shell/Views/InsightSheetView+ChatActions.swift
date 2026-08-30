import Foundation
import SwiftData
import SwiftUI

extension InsightSheetView {
    func appendInsightChatTextToFieldNotes(
        _ text: String,
        kind _: InsightChatFieldNotesAppendKind,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              viewModel.isPresentingLocalRecord(
                  scanId: expectedScanId,
                  generation: expectedGeneration
              ) else {
            return
        }

        let title = "Field chat summary"

        let dateText = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .medium,
            timeStyle: .short
        )
        let section = "\(title) - \(dateText)\n\(trimmed)"
        let existing = viewModel.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = existing.isEmpty ? section : "\(existing)\n\n\(section)"

        viewModel.updateFieldNotes(
            combined,
            expectedScanId: expectedScanId,
            expectedGeneration: expectedGeneration,
            modelContext: modelContext
        )
        viewModel.state.dismissedFieldNotesCardScanId = nil
    }

    func openIdentificationConcernCandidatesFromChat(
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard viewModel.isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        pendingInsightChatDismissalAction = .reviewAlternatives(
            scanId: expectedScanId,
            generation: expectedGeneration
        )
        viewModel.state.isInsightChatSheetPresented = false
    }

    func startReanalysisFromInsightChat(
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard viewModel.isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        guard dependencies.isProActive() else {
            pendingInsightChatDismissalAction = .showPaywall(
                scanId: expectedScanId,
                generation: expectedGeneration
            )
            viewModel.state.isInsightChatSheetPresented = false
            return
        }

        pendingInsightChatDismissalAction = .reanalyze(
            scanId: expectedScanId,
            generation: expectedGeneration
        )
        viewModel.state.isInsightChatSheetPresented = false
    }

    func resumePendingInsightChatDismissalAction() {
        let action = pendingInsightChatDismissalAction
        pendingInsightChatDismissalAction = nil
        selectedInsightChatScanId = nil
        selectedInsightChatGeneration = nil

        guard let action else { return }
        let context = action.context
        guard viewModel.isPresentingLocalRecord(
            scanId: context.scanId,
            generation: context.generation
        ) else {
            return
        }

        switch action {
        case .reviewAlternatives:
            guard viewModel.canReviewIdentificationConcernCandidates else { return }
            viewModel.presentCandidateSwipe(
                source: .identificationConcern,
                expectedScanId: context.scanId,
                expectedGeneration: context.generation
            )
        case .reanalyze:
            dependencies.selectionFeedback()
            dependencies.requestRefinement(
                context.scanId,
                viewModel.shareableFieldNotes
            )
        case .showPaywall:
            viewModel.state.showPaywall = true
        }
    }
}
