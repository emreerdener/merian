import SwiftUI

struct CaptureVideoSavedRequestsSheet: View {
    @Bindable var model: CaptureVideoSavedRequestsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if model.isClosed {
                    Text("Saved requests are no longer available for this observation.")
                } else {
                    Section {
                        ForEach(Array(model.rows.enumerated()), id: \.element.identity.analysisID) { entry in
                            let row = entry.element
                            Button { model.select(row) } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: model.selected == row.identity ? "checkmark.circle.fill" : "circle")
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Saved video request \(entry.offset + 1)").font(.headline)
                                        Text(Self.status(row.phase)).font(.subheadline)
                                    }
                                }
                            }
                            .disabled(model.isBusy)
                            .accessibilityAddTraits(model.selected == row.identity ? .isSelected : [])
                            .accessibilityIdentifier("SavedVideoRequestRow_\(row.identity.analysisID.uuidString.lowercased())")
                        }
                        if model.rows.isEmpty && !model.isBusy {
                            Text(model.message == nil ? "No saved video requests are available on this page." : "This page could not be checked.")
                        }
                        if model.omittedCount > 0 {
                            Text("Some saved requests could not be shown. This does not mean they were removed.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Choose a saved request. Your current identification stays in place. Continuing checks this exact saved video request. It never replaces an uncertain analysis.")
                    }
                    Text("Checking for a result requires an internet connection. Background completion is not guaranteed.")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("SavedVideoConnectivity")
                    Button("View saved video") { model.previewSelected() }
                        .disabled(model.selected == nil || model.isBusy)
                        .accessibilityIdentifier("SavedVideoPreviewOpen")
                    if let preview = model.preview {
                        Section("Original submitted video") {
                            if preview.isReady {
                                MediaCoverVideoPlayer(player: preview.player, videoGravity: .resizeAspect)
                                    .frame(height: 240).accessibilityLabel("Original submitted video")
                                Button(preview.isPlaying ? "Stop video" : "Play video") { preview.toggle() }
                                    .accessibilityIdentifier("SavedVideoPreviewPlay")
                            }
                            if let message = preview.message { Text(message) }
                            Button("Close video preview") { model.closePreview() }
                                .accessibilityIdentifier("SavedVideoPreviewClose")
                        }
                    }
                    Button(actionTitle) { model.continueSelected() }
                        .disabled(model.selected == nil || model.isBusy)
                        .accessibilityIdentifier("SavedVideoRequestContinue")
                    if model.next != nil {
                        Button("More requests") { model.start(more: true) }
                            .disabled(model.isBusy).accessibilityIdentifier("SavedVideoRequestMore")
                    }
                    if let message = model.message {
                        Text(message).accessibilityIdentifier("SavedVideoRequestMessage")
                    }
                    if let message = model.recoveryMessage { Text(message).accessibilityIdentifier("SavedVideoRecoveryMessage") }
                    if model.showsProgress { ProgressView().accessibilityLabel("Checking saved video requests") }
                }
            }
            .navigationTitle("Saved video requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.start() }
                        .disabled(model.isBusy || model.isClosed).accessibilityIdentifier("SavedVideoRequestRefresh")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.close(); dismiss() }.accessibilityIdentifier("SavedVideoRequestDone")
                }
            }
        }
        .accessibilityIdentifier("SavedVideoRequestSheet")
        .presentationDetents([.large])
        .task { model.start() }
        .task(id: model.preview != nil) {
            while let preview = model.preview, !preview.isClosed, !Task.isCancelled {
                preview.checkScope()
                guard !preview.isClosed else { return }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
        .onChange(of: model.isCurrent, initial: true) { _, current in if !current { model.close() } }
        .onChange(of: scenePhase) { _, phase in model.setVisible(phase == .active) }
        .onDisappear { model.close() }
    }

    private var actionTitle: String {
        model.selected == nil ? "Choose a request" : "Check saved request"
    }

    static func status(_ phase: ObservationVideoSavedStatus.Phase) -> String {
        switch phase {
        case .filesPending: "Video preparation needs checking"
        case .prepared: "Video prepared"
        case .reservationStaged: "Request saved"
        case .reservationRunning: "Request check needs recovery"
        case .reservationUnknown: "Request outcome is not confirmed"
        case .reserved: "Ready to upload"
        case .reservationHeld: "Request cannot continue yet"
        case .reservationUnavailable: "Request is unavailable"
        case .reservationConflict: "Saved request needs attention"
        case .uploadPending: "Upload is pending"
        case .uploadRunning: "Upload needs checking"
        case .uploadUnknown: "Upload outcome is not confirmed"
        case .uploadReady: "Video uploaded; ready to continue"
        case .executionIdle: "Analysis request is ready"
        case .executionRunning: "Analysis needs checking"
        case .executionHeld: "Analysis cannot continue yet"
        case .outcomeRecovery: "Original analysis result needs checking"
        }
    }
}
