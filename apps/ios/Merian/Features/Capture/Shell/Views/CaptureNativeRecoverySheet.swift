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
                    case .savedResults(let kind):
                        Text(kind == .retained ? "Saved results awaiting History" : "Interrupted History updates")
                            .font(.headline)
                        if model.savedInitialPage?.candidates.isEmpty == true {
                            Text("No matching results on this page.")
                        }
                        ForEach(Array((model.savedInitialPage?.candidates ?? []).enumerated()), id: \.element.packageID) { entry in
                            Button("Saved result \(entry.offset + 1)") { Task { await model.selectSavedInitial(entry.element) } }
                                .accessibilityIdentifier("NativeRecoverySavedSelect_\(entry.offset)")
                        }
                        if model.savedInitialPage?.next != nil {
                            Button("Next page") { Task { await model.findSavedInitial(kind, next: true) } }
                                .disabled(!model.canReadSavedInitial)
                                .accessibilityIdentifier("NativeRecoverySavedNext")
                        }
                    case .holding:
                        Text("Local submission found")
                            .font(.headline)
                            .accessibilityIdentifier("NativeRecoveryHolding")
                        if model.hasStatusAction {
                            observationStatus
                        } else {
                            Text("Status checking is not available from this view yet. Your current draft and identification are unchanged.")
                        }
                        if model.hasOriginalAction {
                            Button("View original photos") { Task { await model.viewOriginal() } }
                                .disabled(!model.canViewOriginal)
                                .accessibilityIdentifier("NativeRecoveryViewOriginal")
                        }
                        originalPreview
                        if model.hasHistoryAction { historyStatus }
                        Button("Refresh local status") { Task { await model.refresh() } }
                            .accessibilityIdentifier("NativeRecoveryRefresh")
                            .disabled(model.observationStatus == .reserving || model.observationStatus == .checking || model.historyStatus == .saving)
                    }
                }
                if model.isCurrent && model.hasSavedDiscovery {
                    Button("Find saved results") { Task { await model.findSavedInitial(.retained) } }
                        .disabled(!model.canReadSavedInitial)
                        .accessibilityIdentifier("NativeRecoveryFindSaved")
                    Button("Find interrupted History updates") { Task { await model.findSavedInitial(.enrollment) } }
                        .disabled(!model.canReadSavedInitial)
                        .accessibilityIdentifier("NativeRecoveryFindHistoryRecovery")
                }
                Text("Close leaves the submission in place. It does not cancel, delete or repeat analysis.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Checking recorded status requires an internet connection. Background completion is not guaranteed.")
                    .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("NativeRecoveryConnectivity")
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

    @ViewBuilder private var originalPreview: some View {
        if let preview = model.originalPreview {
            Text("Original submitted photo \(preview.index + 1) of \(preview.count)").font(.headline)
            Image(preview.image.cgImage, scale: 1, label: Text("Original submitted photo \(preview.index + 1)"))
                .resizable().scaledToFit().frame(maxHeight: 320)
                .accessibilityIdentifier("NativeRecoveryOriginalImage")
            HStack {
                Button("Previous photo") { Task { await model.viewOriginal(index: preview.index - 1) } }
                    .disabled(!model.canViewOriginal || preview.index == 0)
                Button("Next photo") { Task { await model.viewOriginal(index: preview.index + 1) } }
                    .disabled(!model.canViewOriginal || preview.index + 1 >= preview.count)
            }
            Button("Close photo") { model.closeOriginal() }.accessibilityIdentifier("NativeRecoveryCloseOriginal")
                .task {
                    while !Task.isCancelled && model.originalPreview != nil {
                        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                        await model.checkOriginalScope()
                    }
                }
        } else if model.originalUnavailable {
            Text("The original photos could not be verified. Your submission is preserved.")
        }
    }

    @ViewBuilder private var historyStatus: some View {
        switch model.historyStatus {
        case .saving:
            ProgressView("Adding result to History…")
        case .held:
            Text("The result could not be confirmed in History. Your submission is preserved.")
        case .saved:
            Text("Result saved in History. Your current selection is unchanged.")
                .accessibilityIdentifier("NativeRecoveryHistorySaved")
            Button("Open result") { if model.openSavedResult() { close() } }
                .disabled(!model.canOpenSavedResult)
                .accessibilityIdentifier("NativeRecoveryOpenResult")
        case .idle:
            EmptyView()
        }
        Button("Add result to History") { model.addToHistory() }
            .disabled(!model.canAddToHistory)
            .accessibilityIdentifier("NativeRecoveryAddHistory")
    }

    @ViewBuilder private var observationStatus: some View {
        if model.recordObserved && model.historyStatus == .idle {
            Text("A server record was observed. The original result has not been confirmed.")
                .accessibilityIdentifier("NativeRecoveryResultAvailable")
        }
        switch model.observationStatus {
        case .checking:
            ProgressView("Checking recorded status…")
        case .reserving:
            Text("Preparing status check…")
        case .needsAttention:
            Text("Needs attention. Analysis may still be running. Checking again does not repeat analysis.")
        case .paused:
            Text("Status checking paused. Your submission is unchanged.")
        case .unavailable, .idle, .observed:
            EmptyView()
        }
        if model.observationStatus == .checking || model.observationStatus == .reserving {
            Button("Pause checking") { model.pauseChecking() }
                .accessibilityIdentifier("NativeRecoveryPause")
        } else {
            Button("Check status") { model.checkStatus() }
                .disabled(!model.canCheckStatus)
                .accessibilityIdentifier("NativeRecoveryCheckResult")
        }
    }
}
