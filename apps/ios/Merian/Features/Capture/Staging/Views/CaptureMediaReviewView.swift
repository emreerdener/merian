import SwiftUI

/// Child pages and Field notes share this presentation and its one toolbar.
struct CaptureMediaReviewView: View {
    @Bindable var workspace: CaptureWorkspaceViewModel
    @Bindable var session: CaptureMediaReviewSession
    let onSubmit: () async -> Void

    @State private var previewLifetime: MediaPlaybackLifetime?
    @State private var previewGeneration = UUID()
    @State private var editor: CapturePhotoEditorState?
    @State private var videoEditor: CaptureVideoEditorState?
    @State private var videoLoadFailed = false
    @State private var showsCommitError = false
    @State private var showsRemovalOptions = false
    @State private var command: Task<Void, Never>?

    private var selectedNode: StagedCaptureNode? {
        workspace.stagedCapture.orderedNodes.first { $0.id == session.selectedNodeID }
    }
    private var isBusy: Bool {
        command != nil || workspace.isDraftMutationLocked || workspace.photoReviewCommit != nil
    }
    private var isPrimaryReady: Bool {
        if command == nil, workspace.isCurrentMediaReview(session), workspace.canRetryInitialDraft { return true }
        guard !isBusy, workspace.isCurrentMediaReview(session) else { return false }
        if case .image(_, let image) = selectedNode {
            return editor?.original.id == image.original.id
        }
        return workspace.canSubmitDraft
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            Group {
                if workspace.isFieldNotesOccupied, editor == nil {
                    // Retire playback before dictation acquires the audio session.
                    Color.black
                } else { page }
            }
                .disabled(isBusy || workspace.isFieldNotesOccupied)
                .accessibilityHidden(workspace.isFieldNotesOccupied)
                .safeAreaInset(edge: .bottom) {
                    if !workspace.isFieldNotesOccupied { toolbar.padding(.vertical, 8) }
                }
            if let notes = workspace.fieldNotesSession {
                CaptureFieldNotesOverlay(workspace: workspace, session: notes,
                    speechManager: workspace.diContainer.speechManager) { toolbar }
                    .id(notes.id)
            }
        }
        .sheet(isPresented: Binding(get: { session.historicalDescriptionID != nil }, set: {
            if !$0 { session.historicalDescriptionID = nil }
        })) { historicalDescription }
        .preferredColorScheme(.dark)
        .task(id: "\(session.selectedNodeID ?? "")-\(workspace.initialDraftResources?.id.uuidString ?? "legacy")") {
            updateEditor()
            await loadVideoEditor()
        }
        .onChange(of: workspace.stagedCapture.physicalItemCount) { _, _ in workspace.reconcileMediaReviewSelection() }
        .onChange(of: workspace.isDraftMutationLocked) { _, locked in
            if !locked { workspace.reconcileMediaReviewSelection() }
        }
        .onChange(of: workspace.draftSession.generation) { _, _ in
            if !workspace.isCurrentMediaReview(session) { workspace.dismissMediaReview(sessionID: session.id) }
        }
        .onDisappear { command?.cancel() }
        .confirmationDialog("Remove media", isPresented: $showsRemovalOptions, titleVisibility: .hidden) {
            Button("Remove \(mediaName)", role: .destructive) { removeAfterPlayback() }
            Button(workspace.isReanalyzing ? "Discard reanalysis…" : "Discard observation…", role: .destructive) {
                workspace.requestDraftDiscard()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(workspace.isReanalyzing ? "Discard reanalysis?" : "Discard observation?",
            isPresented: Binding(get: { workspace.discardConfirmationGeneration != nil }, set: {
                if !$0 { workspace.discardConfirmationGeneration = nil }
            }), presenting: workspace.discardConfirmationGeneration) { generation in
                Button("Keep editing", role: .cancel) { workspace.discardConfirmationGeneration = nil }
                Button("Discard", role: .destructive) {
                    command = Task { @MainActor in
                        defer { command = nil; previewGeneration = UUID() }
                        await closePreview()
                        guard !Task.isCancelled, workspace.isCurrentMediaReview(session) else { return }
                        _ = workspace.confirmDraftDiscard(generation: generation)
                    }
                }
            } message: { _ in
                Text(workspace.isReanalyzing
                    ? "Your added media and details will be removed. The original observation will be kept."
                    : "All added photos, recordings, and details will be removed.")
            }
        .alert("Unable to update media", isPresented: $showsCommitError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Your media and edits are kept. Please try again.") }
    }

    @ViewBuilder private var page: some View {
        let previewNode = session.selectedNodeID
        let generation = previewGeneration
        let resources = workspace.initialDraftResources
        switch selectedNode {
        case .image(_, let image):
            if let editor, editor.original.id == image.original.id { CapturePhotoReviewPage(editor: editor) { requestRemoval() } }
        case .audio(_, let audio):
            StagedAudioPreviewModal(audio: audio, resources: workspace.initialDraftResources, onPlaybackReady: { acceptPreview($0, node: previewNode, generation: generation, resources: resources) }, onRemove: { requestRemoval() })
                .id("\(audio.id)-\(previewGeneration)-\(resources?.id.uuidString ?? "legacy")")
        case .video(_, let video):
            if let videoEditor, videoEditor.videoID == video.id {
                StagedVideoPreviewModal(video: video, editor: videoEditor, resources: workspace.initialDraftResources, onPlaybackReady: { acceptPreview($0, node: previewNode, generation: generation, resources: resources) }, onRemove: { requestRemoval() })
                    .id("\(video.id)-\(previewGeneration)-\(resources?.id.uuidString ?? "legacy")")
            } else if videoLoadFailed {
                VStack(spacing: 16) {
                    Text("Video preview unavailable. Your staged media is kept.")
                    Button("Retry preview") { Task { await loadVideoEditor() } }
                }.padding()
            } else { ProgressView("Preparing preview…") }
        case .description, .none:
            ProgressView()
        }
    }

    private var mediaName: String {
        switch selectedNode {
        case .image: return "photo"
        case .audio: return "audio"
        case .video: return "video"
        case .description, .none: return "media"
        }
    }

    private func requestRemoval() {
        guard !isBusy, workspace.isCurrentMediaReview(session) else { return }
        if workspace.stagedCapture.physicalItemCount > 1 || !workspace.descriptionDraft.isEmpty
            || !workspace.stagedCapture.observationContexts.isEmpty {
            showsRemovalOptions = true
        } else { removeAfterPlayback() }
    }

    private func acceptPreview(_ lifetime: MediaPlaybackLifetime, node: String?, generation: UUID,
                               resources: CaptureDraftPresentationResources?) {
        guard !Task.isCancelled, session.selectedNodeID == node, previewGeneration == generation,
              workspace.isCurrentMediaReview(session) else {
            lifetime.seal()
            Task {
                if let resources { await resources.releasePlayback(lifetime) } else { await lifetime.close() }
            }
            return
        }
        previewLifetime = lifetime
    }

    private func closePreview() async {
        guard let lifetime = previewLifetime else { return }
        if let resources = workspace.initialDraftResources { await resources.releasePlayback(lifetime) } else { await lifetime.close() }
        if previewLifetime === lifetime { previewLifetime = nil }
    }

    private func removeAfterPlayback() {
        command = Task { @MainActor in
            defer { command = nil; previewGeneration = UUID() }
            await closePreview()
            guard !Task.isCancelled, workspace.isCurrentMediaReview(session) else { return }
            workspace.removeReviewedMedia(session: session)
        }
    }

    private var toolbar: some View {
        ActiveScanToolbar(
            stagedCapture: workspace.stagedCapture, isRefining: workspace.isReanalyzing,
            stagedCaptureLimit: workspace.stagedCaptureLimit, isSubmissionReady: isPrimaryReady,
            isMutationLocked: isBusy, isNotesPresented: workspace.isFieldNotesOccupied,
            allowsFrozenRequestActions: command == nil && workspace.canRetryInitialDraft,
            selectedNodeID: workspace.isFieldNotesOccupied ? nil : session.selectedNodeID,
            primaryActionTitle: workspace.isReanalyzing ? "Reanalyze" : "Identify",
            onAddMore: { perform(.addMore) },
            onNoteTap: {
                if let notes = workspace.fieldNotesSession { workspace.closeFieldNotes(sessionID: notes.id) } else { perform(.fieldNotes) }
            },
            onUpgradeTap: { perform(.addMore) },
            selectedPhotoItems: $workspace.selectedPhotoItems,
            onRequestPhotoPickerPresentation: { _ in false },
            onThumbnailTap: { index in
                guard workspace.stagedCapture.images.indices.contains(index) else { return }
                perform(.selectMedia("img_\(workspace.stagedCapture.images[index].original.id)"))
            },
            onCancel: { workspace.requestDraftDiscard() }, onSubmit: { perform(.identify) },
            onDescriptionTap: { index in
                guard workspace.stagedCapture.observationContexts.indices.contains(index) else { return }
                perform(.historicalDescription(workspace.stagedCapture.observationContexts[index].id))
            },
            onAudioTap: { index in
                guard workspace.stagedCapture.audios.indices.contains(index) else { return }
                perform(.selectMedia("audio_\(workspace.stagedCapture.audios[index].id)"))
            },
            onVideoTap: { index in
                guard workspace.stagedCapture.videos.indices.contains(index) else { return }
                perform(.selectMedia("video_\(workspace.stagedCapture.videos[index].id)"))
            }, dependencies: workspace.dependencies.stagingToolbar)
    }

    @ViewBuilder private var historicalDescription: some View {
        if let id = session.historicalDescriptionID,
           let context = workspace.stagedCapture.observationContexts.first(where: { $0.id == id }) {
            StagedDescriptionSheet(initialText: context.context.freeText, onSave: { text in
                guard workspace.isCurrentMediaReview(session),
                      let index = workspace.stagedCapture.observationContexts.firstIndex(where: { $0.id == id }) else { return }
                var pending = workspace.descriptionDraft
                workspace.saveStagedDescription(at: index, text: text, pendingDraft: &pending)
                workspace.descriptionDraft = pending
                session.historicalDescriptionID = nil
            }, onRemove: {
                guard workspace.isCurrentMediaReview(session),
                      let index = workspace.stagedCapture.observationContexts.firstIndex(where: { $0.id == id }) else { return }
                var pending = workspace.descriptionDraft
                workspace.removeStagedDescription(at: index, pendingDraft: &pending)
                workspace.descriptionDraft = pending
                session.historicalDescriptionID = nil
            })
        }
    }

    private func updateEditor() {
        videoEditor = nil
        videoLoadFailed = false
        if case .image(_, let image) = selectedNode {
            editor = CapturePhotoEditorState(original: image.original,
                allowsManualSelection: workspace.canSelectPhotoSubject(image),
                usesFullAspect: image.startsWithFullAspectReview)
        } else { editor = nil }
    }

    private func loadVideoEditor() async {
        guard case .video(_, let video) = selectedNode else { return }
        videoLoadFailed = false
        do {
            let loaded: CaptureVideoEditorState
            if let resources = workspace.initialDraftResources {
                loaded = try await resources.read { try await CaptureVideoEditorState.load(video: video) }
            } else {
                loaded = try await CaptureVideoEditorState.load(video: video)
            }
            guard !Task.isCancelled, workspace.isCurrentMediaReview(session),
                  session.selectedNodeID == "video_\(video.id)" else { return }
            videoEditor = loaded
        } catch {
            if !Task.isCancelled, workspace.isCurrentMediaReview(session),
               session.selectedNodeID == "video_\(video.id)" { videoLoadFailed = true }
        }
    }

    private func perform(_ action: CapturePhotoReviewAction) {
        if action == .identify, command == nil, workspace.isCurrentMediaReview(session), workspace.canRetryInitialDraft {
            command = Task { @MainActor in
                defer { command = nil; previewGeneration = UUID() }
                await closePreview()
                guard !Task.isCancelled, workspace.isCurrentMediaReview(session), workspace.canRetryInitialDraft else { return }
                await onSubmit()
            }
            return
        }
        guard !isBusy, workspace.isCurrentMediaReview(session) else { return }
        if case .selectMedia(let nodeID) = action, nodeID == session.selectedNodeID { return }
        if action == .fieldNotes {
            command = Task { @MainActor in
                defer { command = nil; previewGeneration = UUID() }
                await closePreview()
                guard !Task.isCancelled, workspace.isCurrentMediaReview(session) else { return }
                _ = workspace.openFieldNotes(inReview: session)
            }
            return
        }
        if case .historicalDescription(let id) = action {
            session.historicalDescriptionID = id
            return
        }
        let notes = workspace.fieldNotesSession
        if let notes {
            guard action == .identify, workspace.acceptsFieldNotesWrite(notes), !notes.isSubmitting else { return }
            notes.isSubmitting = true
            notes.errorMessage = nil
        }
        command = Task { @MainActor in
            defer { command = nil; notes?.isSubmitting = false; previewGeneration = UUID() }
            await closePreview()
            guard !Task.isCancelled, workspace.isCurrentMediaReview(session) else { return }
            if let notes {
                let finalized = await notes.input.finishDictation { notes.isDictationRequested = false }
                guard workspace.acceptsFieldNotesWrite(notes), workspace.isCurrentMediaReview(session), !Task.isCancelled else { return }
                guard finalized else {
                    notes.errorMessage = "Dictation could not finish. Your notes are kept. Review them before identifying."
                    return
                }
            }
            if let editor, case .image(_, let image) = selectedNode {
                guard let commit = workspace.beginPhotoReviewCommit(imageID: image.original.id,
                    action: action, notesSessionID: notes?.id) else { return }
                let shouldSubmit: Bool
                if !editor.hasEdits, !editor.hasSelectionEdits,
                   workspace.canPreservePhotoReviewArtifacts(imageID: image.original.id) {
                    shouldSubmit = workspace.finishPhotoReviewCommit(commit, succeeded: true)
                } else {
                    let preservesPixels = !editor.hasEdits && !image.compressedData.isEmpty
                    let data = preservesPixels ? image.compressedData : await editor.generateCrop()
                    guard !Task.isCancelled, workspace.isCurrentPhotoReviewCommit(commit) else {
                        _ = workspace.finishPhotoReviewCommit(commit, succeeded: false)
                        return
                    }
                    guard !data.isEmpty else {
                        _ = workspace.finishPhotoReviewCommit(commit, succeeded: false)
                        showsCommitError = true
                        return
                    }
                    shouldSubmit = await workspace.commitPhotoReview(commit, croppedData: data,
                        scale: editor.scale, offset: editor.offset, displaySize: editor.displaySize,
                        quarterTurns: editor.quarterTurns, sourceSelection: editor.sourceSelection,
                        preservesPixels: preservesPixels)
                }
                guard workspace.completedPhotoReviewCommitID == commit.id else {
                    if workspace.isCurrentMediaReview(session), !Task.isCancelled { showsCommitError = true }
                    return
                }
                // A successful commit is the baseline for any later notes or recrop.
                if session.selectedNodeID == "img_\(commit.imageID)" { updateEditor() }
                if shouldSubmit, !Task.isCancelled { await onSubmit() }
            } else {
                if let videoEditor, case .video(_, let video) = selectedNode,
                   videoEditor.videoID == video.id, videoEditor.crop.hasEdits {
                    guard await workspace.commitVideoReview(videoEditor, session: session, notesSessionID: notes?.id) else {
                        if workspace.isCurrentMediaReview(session), !Task.isCancelled { showsCommitError = true }
                        return
                    }
                    self.videoEditor = nil
                    await loadVideoEditor()
                    guard !Task.isCancelled, workspace.isCurrentMediaReview(session) else { return }
                }
                switch action {
                case .selectMedia(let nodeID): _ = workspace.presentMediaReview(nodeID: nodeID)
                case .fieldNotes: _ = workspace.openFieldNotes(inReview: session)
                case .historicalDescription(let id): session.historicalDescriptionID = id
                case .addMore: workspace.dismissMediaReview(sessionID: session.id)
                case .identify: if workspace.canSubmitDraft { await onSubmit() }
                }
            }
            if workspace.isCurrentMediaReview(session), workspace.isDraftMutationLocked {
                // A retained owner now controls frozen retry/recovery. Return to its
                // existing root actions without changing the saved request.
                workspace.dismissMediaReview(sessionID: session.id)
                return
            }
            if workspace.isCurrentMediaReview(session), case .image(_, let image) = selectedNode,
               workspace.imageToCrop == nil {
                workspace.imageToCrop = image.original
            }
        }
        if let command { workspace.replaceActiveCropTask(with: command) }
    }
}
