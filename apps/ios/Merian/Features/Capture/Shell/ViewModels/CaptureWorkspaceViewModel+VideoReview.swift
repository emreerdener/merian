import Foundation

extension CaptureWorkspaceViewModel {
    /// Produces candidates off the retained source, then swaps the full set on
    /// the main actor. No prior derivative is deleted until the swap succeeds.
    func commitVideoReview(_ editor: CaptureVideoEditorState, session: CaptureMediaReviewSession,
                           notesSessionID: UUID? = nil) async -> Bool {
        if initialDraftSession != nil {
            return await commitInitialVideoReview(editor, review: session, notesSessionID: notesSessionID)
        }
        let submittingNotes = fieldNotesSession.map {
            $0.id == notesSessionID && $0.isSubmitting && acceptsFieldNotesWrite($0)
        } ?? false
        guard !isDraftMutationLocked, photoReviewCommit == nil, videoReviewCommitID == nil,
              !isFieldNotesOccupied || submittingNotes, !draftSession.hasUnresolvedWork,
              isCurrentMediaReview(session), session.selectedNodeID == "video_\(editor.videoID)",
              let video = stagedCapture.videos.first(where: { $0.id == editor.videoID }),
              draftOwnedFiles.contains(editor.sourcePath) else { return false }
        if !editor.crop.hasEdits { return true }
        let token = UUID()
        videoReviewCommitID = token
        defer { if videoReviewCommitID == token { videoReviewCommitID = nil } }
        do {
            let framing = editor.framing
            let prepared = try await dependencies.scan.media.prepareVideo(.init(videoURL: editor.sourceURL,
                duration: editor.duration, composingCenter: video.composingCenter,
                isProActive: dependencies.scan.canStartProScan(), framing: framing))
            let candidatePaths = [prepared.playback.fileURL.path, prepared.audioFilePath].compactMap { $0 }
            guard !Task.isCancelled, videoReviewCommitID == token, isCurrentMediaReview(session),
                  session.selectedNodeID == "video_\(editor.videoID)",
                  let index = stagedCapture.videos.firstIndex(where: { $0.id == editor.videoID }),
                  stagedCapture.videos[index].filePath == video.filePath,
                  draftOwnedFiles.contains(editor.sourcePath) else {
                discardLocalMediaFiles(at: candidatePaths.filter { $0 != editor.sourcePath && $0 != editor.sourceURL.path })
                return false
            }
            let replacement = Self.makeStagedVideo(prepared, id: video.id, addedAt: video.addedAt,
                originalFilePath: editor.sourcePath, composingCenter: video.composingCenter, framing: framing)
            let superseded = [video.filePath, video.audioFilePath].compactMap { $0 }
                .filter { $0 != editor.sourcePath && $0 != editor.sourceURL.path && !candidatePaths.contains($0) && draftOwnedFiles.contains($0) }
            draftOwnedFiles.formUnion(candidatePaths)
            stagedCapture.videos[index] = replacement
            draftOwnedFiles.subtract(superseded)
            discardLocalMediaFiles(at: superseded)
            return true
        } catch { return false }
    }
}
