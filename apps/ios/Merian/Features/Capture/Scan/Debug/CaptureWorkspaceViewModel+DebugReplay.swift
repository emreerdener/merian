#if DEBUG && targetEnvironment(simulator)
import Foundation

extension CaptureWorkspaceViewModel {
    var hasFixedContextDebugReplay: Bool {
        stagedCapture.audios.contains { $0.debugReplayProfile != nil }
    }

    var canSubmitFixedContextDebugReplay: Bool {
        stagedCapture.totalItemCount == 1 && stagedCapture.audios.count == 1
            && stagedCapture.audios.first?.debugReplayProfile != nil
            && baseRefinementContext == nil
    }

    var canStartDebugReplay: Bool {
        !isCapturing && !isVideoRecording && !isPreparingVideo
            && !isCheckingScanAdmission && !isStagingRefinement
            && activeSheet == nil && !isRootPresentationDismissing
            && imageToCrop == nil && selectedPhotoItems.isEmpty
            && stagedCapture.isEmpty && baseRefinementContext == nil
            && !diContainer.supabaseManager.isAuthTransitionInProgress
            && !diContainer.audioCaptureManager.isRecording
            && diContainer.audioCaptureManager.pendingPlaybackPath == nil
    }

    @discardableResult
    func startDebugReplay(
        _ kind: CaptureDebugReplayKind,
        profile: DebugIdentificationReplayProfile? = nil,
        prepare: @escaping @Sendable (CaptureDebugReplayKind, CGFloat, Bool, (any DebugAudioComparisonBinding)?) async throws -> PreparedCaptureDebugReplay = {
            try await CaptureDebugReplayPreparer.prepare($0, composingCenter: $1, isProActive: $2, comparison: $3)
        }
    ) -> Task<Void, Never>? {
        guard canStartDebugReplay, profile == nil || kind == .audio,
              kind != .video || dependencies.scan.canStartProScan() else { return nil }
        if profile != nil {
            preFetchTask?.cancel()
            preFetchTask = nil
        }
        let generation = UUID()
        let accountGeneration = diContainer.appRouteCoordinator.accountGeneration
        let sessionGeneration = diContainer.appRouteCoordinator.sessionGeneration
        let userID = diContainer.supabaseManager.currentUser?.id
        debugReplayGeneration = generation
        isCapturing = true
        finishAutomaticStagedSubmissionAttempt()
        let composingCenter = composingZoneVerticalCenter
        let isProActive = dependencies.scan.canStartProScan()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.debugReplayGeneration == generation {
                    self.debugReplayGeneration = nil
                    self.debugReplayTask = nil
                    self.isCapturing = false
                }
            }
            do {
                let prepared = try await prepare(kind, composingCenter, isProActive, profile?.comparison)
                if let assignment = profile?.comparison {
                    do {
                        guard case .audio(let url) = prepared else { throw CaptureDebugReplayError.comparisonMismatch }
                        let matches = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                            try Task.checkCancellation()
                            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                            guard values.isRegularFile == true, values.isSymbolicLink != true,
                                  values.fileSize == assignment.sourceByteLength else { return false }
                            return assignment.matchesSource(try Data(contentsOf: url))
                        }
                        guard matches else { throw CaptureDebugReplayError.comparisonMismatch }
                    } catch {
                        await prepared.discard()
                        throw error
                    }
                }
                guard !Task.isCancelled,
                      self.debugReplayGeneration == generation,
                      self.diContainer.appRouteCoordinator.accountGeneration == accountGeneration,
                      self.diContainer.appRouteCoordinator.sessionGeneration == sessionGeneration,
                      self.diContainer.supabaseManager.currentUser?.id == userID,
                      !self.diContainer.supabaseManager.isAuthTransitionInProgress,
                      self.stagedCapture.isEmpty, self.baseRefinementContext == nil,
                      self.activeSheet == nil, self.imageToCrop == nil else {
                    await prepared.discard()
                    return
                }
                switch prepared {
                case .audio(let url):
                    self.stagedCapture.audios.append(StagedAudio(
                        filePath: url.lastPathComponent, debugReplayProfile: profile
                    ))
                case .video(let video):
                    self.stagedCapture.videos.append(Self.makeStagedVideo(video, isFromGallery: true))
                }
                // Deliberately retain manual Identify ownership even in single-capture mode.
                self.finishAutomaticStagedSubmissionAttempt()
            } catch is CancellationError {
                // Preparation owns cleanup until it returns an accepted result.
            } catch {
                guard self.debugReplayGeneration == generation else { return }
                self.offlineToastMessage = .error(
                    (error as? CaptureDebugReplayError)?.errorDescription
                        ?? "Replay couldn't prepare the sample. Check the local file and try again."
                )
            }
        }
        debugReplayTask = task
        return task
    }

    func cancelDebugReplay() {
        guard debugReplayGeneration != nil else { return }
        debugReplayGeneration = nil
        debugReplayTask?.cancel()
        debugReplayTask = nil
        isCapturing = false
    }
}
#endif
