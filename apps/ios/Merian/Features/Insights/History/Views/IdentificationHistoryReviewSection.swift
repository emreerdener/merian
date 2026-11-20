import SwiftUI

struct IdentificationHistoryReviewSection: View {
    @Bindable var model: IdentificationHistoryReviewModel
    var onReviewCandidates: (() -> Void)?
    @State private var scientificName = ""
    @State private var pendingConfirmationUndo: (() -> Void)?

    var body: some View {
        Section {
            if let onReviewCandidates, !model.ticket.candidateChoices.isEmpty {
                Button("Review alternatives", action: onReviewCandidates)
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("HistoryReviewCandidates")
            }
            if model.ticket.canConfirmPrimary, let name = model.ticket.primaryScientificName {
                Button("Confirm \(name)") { model.submit(.confirmPrimary) }
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("HistoryConfirmPrimary")
            }
            if model.ticket.canConfirmName {
                TextField("Scientific species name", text: $scientificName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("HistorySpeciesName")
                Button("Confirm this species name") { model.submit(.confirmName(scientificName)) }
                    .disabled(!model.canSubmit || !validName)
                    .accessibilityIdentifier("HistoryConfirmName")
            }
            if model.ticket.canReject {
                Button("Mark this identification incorrect", role: .destructive) { model.submit(.reject) }
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("HistoryReject")
            }
            if let undo = model.confirmationUndo {
                Button("Undo confirmation") {
                    let action = { model.submit(.undoConfirmation(confirmationOperationID: undo.operationID)) }
                    if undo.action == .name { pendingConfirmationUndo = action } else { action() }
                }
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("HistoryUndoConfirmation")
            }
            if let reason = model.confirmationUndoMessage { Text(reason).font(.callout) }
            if let reason = model.rejectionUndoMessage { Text(reason).font(.callout) }
            if let operation = model.undoOperation {
                Button("Undo incorrect mark") { model.submit(.undo(rejectionOperationID: operation)) }
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("HistoryUndoReview")
            }
            if let message = model.message { Text(message).font(.callout).accessibilityIdentifier("HistoryReviewMessage") }
            if model.canRetrySave {
                Button("Retry saving this review") { model.retrySave() }
                    .accessibilityIdentifier("HistoryRetryReviewSave")
            }
        } header: { Text("Review this identification") } footer: {
            Text("A review applies only to this result. It does not select it or confirm another identification in the history.")
        }
        .task { model.open() }
        .confirmationUndoPrompt(action: $pendingConfirmationUndo)
    }
    private var validName: Bool {
        (try? model.ticket.request(.confirmName(scientificName), operationID: model.ticket.analysisID)) != nil
    }
}
