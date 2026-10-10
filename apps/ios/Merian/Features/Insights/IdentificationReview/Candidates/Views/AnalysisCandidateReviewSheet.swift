import SwiftUI

/// Uses the existing card geometry with explicit immutable evidence inputs.
struct AnalysisCandidateReviewSheet: View {
    @Bindable var model: AnalysisCandidateReviewModel
    let rendering: CandidateReviewRendering
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !model.isScopeCurrent {
                        Text("This identification changed. Open a fresh preview to review it.")
                    } else if model.review.request == nil {
                        ForEach(model.remaining) { choice in
                            VStack(spacing: 12) {
                                GridSwipeableCell(candidate: choice.display, imageDependencies: rendering.images,
                                    feedback: rendering.feedback, onConfirm: {},
                                    onReject: { model.dismissChoice(choice.reference) }, protectedReview: model,
                                    onImmediateConfirm: { model.submit(choice.reference) })
                                    .frame(height: 420)
                                Button("Confirm \(choice.reference.scientificName)") { model.submit(choice.reference) }
                                    .accessibilityIdentifier("CandidateConfirm_\(choice.reference.ordinal)")
                            }
                            .disabled(!model.canReview)
                        }
                        if model.remaining.isEmpty {
                            Text("No other alternatives")
                            Button("Review again") { model.restart() }.disabled(!model.canReview)
                        }
                    }
                    if let message = model.review.terminalMessage ?? model.review.message { Text(message).accessibilityIdentifier("CandidateReviewStatus") }
                    if model.review.canRetrySave {
                        Button("Retry saving this choice") { model.review.retrySave() }
                            .disabled(!model.isScopeCurrent)
                    }
                    if let message = model.photoMessage { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
                .padding(20)
            }
            .accessibilityIdentifier("CandidateReviewScroll")
            .navigationTitle("Review alternatives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("AnalysisCandidateReviewSheet")
        .task { await model.loadEvidence() }
        .onChange(of: model.isScopeCurrent) { _, current in if !current { model.close() } }
    }
}
