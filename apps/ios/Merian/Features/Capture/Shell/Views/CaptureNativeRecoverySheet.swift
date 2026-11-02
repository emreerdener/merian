import SwiftUI

/// Local discovery plus an optional qualified availability action. Ordinary
/// composition keeps that action unavailable; finding never imports a result.
struct CaptureNativeRecoverySheet: View {
    @Bindable var model: CaptureNativeRecoveryModel
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if !model.isCurrent {
                    Text("Local submission status is no longer available in this session.")
                } else {
                    switch model.state {
                    case .closed:
                        Text("This status view is closed.")
                    case .checking:
                        Text("Checking local submission records…")
                    case .unavailable:
                        Text("Local submission status couldn’t be verified. Closing does not delete the submission.")
                    case .unselected(let candidates):
                        if candidates.isEmpty {
                            Text("No local submission can be shown here. This does not confirm that all pending work is complete.")
                        }
                        ForEach(Array(candidates.enumerated()), id: \.element.packageID) { entry in
                            Button("Pending submission \(entry.offset + 1)") {
                                Task { await model.select(entry.element) }
                            }
                            .accessibilityIdentifier("NativeRecoverySelect_\(entry.offset)")
                        }
                    case .holding:
                        Text("Local submission found")
                            .font(.headline)
                            .accessibilityIdentifier("NativeRecoveryHolding")
                        if model.hasStatusAction {
                            resultStatus
                        } else {
                            Text("Result checking and saved media are not available from this view yet. Your current draft and identification are unchanged.")
                        }
                        Button("Refresh local status") { Task { await model.refresh() } }
                            .accessibilityIdentifier("NativeRecoveryRefresh")
                            .disabled(model.resultStatus == .reserving || model.resultStatus == .checking)
                    }
                }
                Text("Close leaves the submission in place. It does not cancel, delete or repeat analysis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Pending submissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { model.close(); close() }.accessibilityIdentifier("NativeRecoveryClose")
                }
            }
        }
        .accessibilityIdentifier("NativeRecoverySheet")
        .presentationDetents([.large])
        .task { await model.open() }
        .onChange(of: model.isCurrent) { _, current in if !current { close() } }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setVisible(phase == .active)
            if !model.isCurrent { model.close(); close() }
        }
        .onDisappear { model.close() }
    }

    @ViewBuilder private var resultStatus: some View {
        if model.resultAvailable {
            Text("A result is available. It has not been added to History from this view.")
                .accessibilityIdentifier("NativeRecoveryResultAvailable")
        }
        switch model.resultStatus {
        case .checking:
            ProgressView("Checking for a result…")
        case .reserving:
            Text("Preparing result check…")
        case .needsAttention:
            Text("Needs attention. Analysis may still be running. Checking again does not repeat analysis.")
        case .paused:
            Text("Result checking paused. Your submission is unchanged.")
        case .unavailable, .idle, .available:
            EmptyView()
        }
        if model.resultStatus == .checking || model.resultStatus == .reserving {
            Button("Pause checking") { model.pauseChecking() }
                .accessibilityIdentifier("NativeRecoveryPause")
        } else {
            Button("Check for result") { model.checkStatus() }
                .disabled(!model.canCheckStatus)
                .accessibilityIdentifier("NativeRecoveryCheckResult")
        }
    }
}
