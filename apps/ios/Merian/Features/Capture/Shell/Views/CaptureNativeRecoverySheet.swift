import SwiftUI

/// Local receipt discovery only. No result check, editable reconstruction or
/// saved-media action is offered until its separate authority is integrated.
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
                        Text("Result checking and saved media are not available from this view yet. Your current draft and identification are unchanged.")
                        Button("Refresh local status") { Task { await model.refresh() } }
                            .accessibilityIdentifier("NativeRecoveryRefresh")
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
                    Button("Close", action: close).accessibilityIdentifier("NativeRecoveryClose")
                }
            }
        }
        .accessibilityIdentifier("NativeRecoverySheet")
        .presentationDetents([.large])
        .task { await model.open() }
        .onChange(of: model.isCurrent) { _, current in if !current { close() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !model.isCurrent { close() }
        }
        .onDisappear { model.close() }
    }
}
