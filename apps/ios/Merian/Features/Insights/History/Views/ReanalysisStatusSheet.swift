import SwiftUI

struct ReanalysisStatusSheet: View {
    @Bindable var model: ReanalysisStatusViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if model.isClosed {
                    Text("Reanalysis status is no longer available for this scan.")
                } else {
                    Section {
                        ForEach(model.rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(title(row.phase)).font(.headline)
                                Text(detail(row.phase)).font(.callout).foregroundStyle(.secondary)
                                if model.allowsOutcomeRecovery, row.canCheckOutcome {
                                    Button("Check for the original result") { model.checkOutcome(row) }
                                        .disabled(model.isBusy)
                                        .accessibilityIdentifier("ReanalysisOutcome_\(row.id.uuidString.lowercased())")
                                }
                                if model.allowsRetirement, let action = row.retirement {
                                    Button(action == .requestStop ? "Try to stop this reanalysis" : "Check this stop request again") {
                                        model.requestRetirement(row)
                                    }.disabled(model.isBusy)
                                    .accessibilityIdentifier("ReanalysisRetirement_\(row.id.uuidString.lowercased())")
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("ReanalysisStatus_\(row.id.uuidString.lowercased())")
                        }
                        if model.rows.isEmpty && !model.isBusy {
                            Text(model.next == nil ? "No pending reanalyses are available to show." : "No requests are available on this page.")
                        }
                    } footer: {
                        Text("Your current identification stays in place. Completed results appear in identification history.")
                    }
                    if model.next != nil {
                        Button("More requests") { model.start(more: true) }.disabled(model.isBusy).accessibilityIdentifier("ReanalysisStatusMore")
                    }
                    if let message = model.message { Text(message) }
                    if model.isBusy { ProgressView().accessibilityLabel("Loading reanalysis status") }
                }
            }
            .navigationTitle("Reanalysis status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.start() }.disabled(model.isBusy || model.isClosed)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.close(); dismiss() }
                }
            }
        }
        .accessibilityIdentifier("ReanalysisStatusSheet")
        .presentationDetents([.medium, .large])
        .task { model.start() }
        .onChange(of: model.deliveryGeneration) { _, _ in model.refreshForLibraryChange() }
        .onChange(of: model.isSessionCurrent, initial: true) { _, current in if !current { model.close() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.validate() } }
        .onDisappear { model.close() }
    }
    private func title(_ phase: ObservationReanalysisOperationStatus.Phase) -> String {
        switch phase {
        case .stopping: "Checking stop request"
        case .stopNeedsChecking: "Stop request needs checking"
        case .preparingEvidence: "Photo preparation pending"
        case .waitingToStart: "Waiting to continue"
        case .processing: "Result pending"
        case .waitingToRetry: "Waiting to check again"
        case .consentRequired: "AI permission required"
        case .evidenceUnavailable: "Photos unavailable"
        case .reconciliationRequired: "Result needs checking"
        case .retryLimit: "Preparation attempts paused"
        case .executionRetryLimit: "Result checks paused"
        case .terminalFailure: "Reanalysis could not complete"
        }
    }
    private func detail(_ phase: ObservationReanalysisOperationStatus.Phase) -> String {
        switch phase {
        case .stopping: "The app is checking the original request. It will stop only if analysis has not started."
        case .stopNeedsChecking: "The stop could not be confirmed. Checking this request will not start another analysis."
        case .preparingEvidence: "Saved photos are waiting to be prepared for this request."
        case .waitingToStart: "This request is saved and waiting for its requirements to be met."
        case .processing: "This saved request is awaiting processing or recovery. A result has not been confirmed yet."
        case .waitingToRetry: "The app will check this same request again when it can."
        case .consentRequired: "This request is paused because AI processing permission is required."
        case .evidenceUnavailable: "The original photos for this request could not be recovered. The request is paused."
        case .reconciliationRequired: "The outcome could not be confirmed. The request is paused to avoid starting another analysis."
        case .retryLimit: "The app could not finish preparing this request. Preparation attempts have stopped."
        case .executionRetryLimit: "Automatic result checks have stopped. You can check for the original result without starting another analysis."
        case .terminalFailure: "This request ended without a new identification. Your saved identification has been kept."
        }
    }
}
