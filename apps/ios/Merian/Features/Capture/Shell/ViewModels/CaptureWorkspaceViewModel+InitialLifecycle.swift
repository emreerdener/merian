import Foundation

extension CaptureWorkspaceViewModel {
    var hasInitialDraftLiability: Bool {
        initialDraftSession?.journal != nil || initialDraftSession?.sources.isEmpty == false
            || !initialDraftPendingSources.isEmpty || !initialDraftTemporaryFiles.isEmpty || !initialDraftVideoAttempts.isEmpty
    }

    var isInitialDraftWorkActive: Bool {
        initialDraftMutationTask != nil || initialDraftLifecycleTask != nil || initialDraftSession?.isBusy == true
    }

    var canRetryInitialDraft: Bool {
        initialDraftSession?.frozenPlan != nil && !isInitialDraftWorkActive
            && !isCheckingScanAdmission && !isQueueingStagedCapture && isDraftAccountCurrent
            && !draftSession.hasUnresolvedWork && photoReviewCommit == nil && videoReviewCommitID == nil
            && !dependencies.submission.admission.isLibraryAccessBlocked()
    }

    var canDiscardInitialDraft: Bool {
        initialDraftSession != nil && !isInitialDraftWorkActive && isDraftAccountCurrent
            && !isCheckingScanAdmission && !isQueueingStagedCapture
            && photoReviewCommit == nil && videoReviewCommitID == nil
            && !dependencies.submission.admission.isLibraryAccessBlocked()
    }

    /// A failed preview or uncertain original write still has one whole-draft
    /// Identify action. Missing cold sources without retained retry bytes stay
    /// held; they cannot be silently omitted from the observation.
    var canRecoverInitialDraft: Bool {
        guard let session = initialDraftSession, session.frozenPlan == nil, !session.needsPreparationAbort,
              canDiscardInitialDraft, !draftSession.hasUnresolvedWork,
              !isCapturing, !isVideoRecording, !isPreparingVideo,
              imageToCrop == nil, discardConfirmationGeneration == nil else { return false }
        let retryItems = Set(initialDraftPendingSources.map(\.itemID)).union(initialDraftVideoAttempts.keys)
        guard session.sources.allSatisfy({ $0.ready || retryItems.contains($0.itemID) }) else { return false }
        return !retryItems.isEmpty || (!session.sources.isEmpty && stagedCapture.physicalItemCount == 0)
    }

    func recoverInitialDraftSources(_ session: CaptureInitialDraftSession, generation: UUID) async throws {
        for itemID in Array(initialDraftVideoAttempts.keys) {
            try await retainInitialVideoAttempt(itemID: itemID, session: session, generation: generation)
        }
        if !initialDraftPendingSources.isEmpty {
            _ = try await session.retainSources(initialDraftPendingSources.map(\.retention))
            try requireInitialDraft(session, generation: generation)
            initialDraftPendingSources.removeAll()
        }
        guard session.sources.allSatisfy(\.ready) else { throw SharedMediaStorageFailure.closed }
        for itemID in Array(initialDraftTemporaryFiles.keys) { try await retireInitialTemporaryFiles(itemID: itemID) }
    }

    /// A cold editor opens before the next shutter can create another draft.
    /// A frozen projection is disposable display only; it never fills missing
    /// frozen derivatives or changes an accepted observation's membership.
    func restoreInitialDraftIfPossible() {
        guard usesInitialDraftComposition, initialDraftSession == nil, !isInitialDraftWorkActive,
              stagedCapture.isEmpty, !draftSession.hasUnresolvedWork,
              let account = dependencies.submission.admission.accountID(),
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              !diContainer.supabaseManager.isAuthTransitionInProgress,
              bindDraftToCurrentAccount() else { return }
        let generation = draftSession.generation
        let lifecycleID = UUID()
        initialDraftLifecycleID = lifecycleID
        initialDraftLifecycleTask = Task { @MainActor [self] in
            defer {
                if initialDraftLifecycleID == lifecycleID {
                    initialDraftLifecycleTask = nil; initialDraftLifecycleID = nil
                    // An inbox delivery may have deferred while cold restore
                    // owned the draft. Retry after that ownership is released.
                    if isDraftAccountCurrent, draftSession.generation == generation {
                        importPendingExternalImageIfPossible()
                    }
                }
            }
            do {
                let session = try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: account) { [self] in
                    let session = try await resolveInitialDraft()
                    try requireInitialDraft(session, generation: generation)
                    // Shutdown may have rescued a complete producer into the
                    // retry buffer before its first journal write. Reacquire
                    // current authority and retain it before restoring the UI.
                    if session.frozenPlan == nil,
                       !initialDraftPendingSources.isEmpty || !initialDraftVideoAttempts.isEmpty {
                        try await recoverInitialDraftSources(session, generation: generation)
                    }
                    if let notes = initialDraftNotesRecovery {
                        guard notes.identity == session.identity, let journal = session.journal else { throw SharedMediaStorageFailure.conflict }
                        if journal.value.phase == .editing {
                            let media = journal.value.items.filter { if case .description = $0 { return false }; return true }
                            try await session.updateReview(items: media + notes.contexts.map {
                                .description(id: $0.id, text: $0.context.freeText)
                            })
                        } else {
                            // Preparation may have durably frozen during the
                            // retiring task's final save. Its saved request is
                            // authoritative; a memory snapshot cannot edit it.
                            guard session.frozenPlan != nil else { throw SharedMediaStorageFailure.conflict }
                        }
                        try requireInitialDraft(session, generation: generation)
                    }
                    return session
                }
                try requireInitialDraft(session, generation: generation)
                guard session.journal != nil || !session.sources.isEmpty || !initialDraftPendingSources.isEmpty
                    || !initialDraftVideoAttempts.isEmpty else {
                    try await releaseInitialProducerResources()
                    initialDraftSession = nil
                    return
                }
                if session.journal != nil { try await refreshInitialDraftPresentation(session, generation: generation) }
                if let notes = initialDraftNotesRecovery, notes.identity == session.identity {
                    fieldNotesPromptProgress = notes.progress
                    fieldNotesPromptGeneration = generation
                    initialDraftNotesRecovery = nil
                }
                revokeAutomaticSubmission()
            } catch {
                guard isDraftAccountCurrent, draftSession.generation == generation else { return }
                offlineToastMessage = .error("Your retained observation couldn’t be restored yet. Its media is kept.")
            }
        }
    }

    /// Account/auth changes retire private presentation only. Durable journals
    /// remain under their account owner; same-account refresh also keeps exact
    /// in-memory retry bytes whose earlier write was uncertain.
    func invalidateInitialDraftForAccountChange() {
        let previousLifecycle = initialDraftLifecycleTask
        previousLifecycle?.cancel()
        let previousAccount = initialDraftSession?.identity.ownerID ?? initialDraftOwnerID
        let sameAccount = previousAccount != nil && previousAccount == dependencies.submission.admission.accountID()
        if !sameAccount {
            initialDraftNotesRecovery = nil
        } else if let session = initialDraftSession, session.frozenPlan == nil,
                  stagedCapture.physicalItemCount > 0 {
            initialDraftNotesRecovery = .init(identity: session.identity,
                contexts: stagedCapture.observationContexts,
                progress: fieldNotesPromptGeneration == draftSession.generation ? fieldNotesPromptProgress : nil)
        }
        let mutation = initialDraftMutationTask
        mutation?.cancel()
        cancelAllVisualCaptureWork()
        retireMediaReview()
        invalidateFieldNotes(clearProgress: true)
        initialDraftSession = nil
        clearInitialDraftVisibleState()
        let lifecycleID = UUID()
        initialDraftLifecycleID = lifecycleID
        initialDraftLifecycleTask = Task { @MainActor [self] in
            defer { if initialDraftLifecycleID == lifecycleID { initialDraftLifecycleTask = nil; initialDraftLifecycleID = nil } }
            await previousLifecycle?.value
            await mutation?.value
            guard initialDraftLifecycleID == lifecycleID else { return }
            do {
                try await releaseInitialDraftPresentation()
                try await releaseInitialProducerResources()
                if !sameAccount {
                    initialDraftPendingSources.removeAll()
                    initialDraftVideoAttempts.removeAll()
                    for itemID in Array(initialDraftTemporaryFiles.keys) { try await retireInitialTemporaryFiles(itemID: itemID) }
                }
                initialDraftAuthGeneration = nil
                if !sameAccount { initialDraftOwnerID = nil }
                initialDraftLifecycleTask = nil; initialDraftLifecycleID = nil
                restoreInitialDraftIfPossible()
            } catch {
                offlineToastMessage = .error("Local media cleanup is still pending. Your retained originals are kept.")
            }
        }
    }

    func removeInitialDraftItem(_ itemID: UUID) {
        guard let session = initialDraftSession, !isInitialDraftWorkActive,
              session.frozenPlan == nil, !session.needsPreparationAbort else { return }
        let generation = draftSession.generation
        revokeAutomaticSubmission()
        initialDraftMutationTask = Task { @MainActor [self] in
            defer { initialDraftMutationTask = nil; reconcileMediaReviewSelection() }
            do {
                try await releaseInitialDraftPresentation()
                try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: session.identity.ownerID) { [self] in
                    try requireInitialDraft(session, generation: generation)
                    try await session.discard(itemID: itemID)
                    try initialDraftProducerResources?.currentValue().acknowledge(itemID: itemID)
                    initialDraftPendingSources.removeAll { $0.itemID == itemID }
                    initialDraftVideoAttempts[itemID] = nil
                    try await retireInitialTemporaryFiles(itemID: itemID)
                }
                if session.sources.isEmpty {
                    try await releaseInitialProducerResources()
                    initialDraftNotesRecovery = nil
                    initialDraftSession = nil
                    clearInitialDraftVisibleState()
                } else {
                    try await refreshInitialDraftPresentation(session, generation: generation)
                }
            } catch {
                guard initialDraftSession === session, isDraftAccountCurrent else { return }
                offlineToastMessage = .error("Removal couldn’t finish. Your observation is retained; try again.")
            }
        }
    }

    func discardInitialDraft() {
        guard let session = initialDraftSession, !isInitialDraftWorkActive else { return }
        let generation = draftSession.generation
        revokeAutomaticSubmission()
        initialDraftMutationTask = Task { @MainActor [self] in
            defer { initialDraftMutationTask = nil }
            do {
                try await releaseInitialDraftPresentation()
                try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: session.identity.ownerID) { [self] in
                    try requireInitialDraft(session, generation: generation)
                    // The native owner independently refuses abort after an
                    // accepted parent; UI state never grants deletion authority.
                    if session.frozenPlan != nil || session.needsPreparationAbort { try await session.abortPreparation() }
                    for itemID in Set(session.sources.map(\.itemID)) { try await session.discard(itemID: itemID) }
                    try initialDraftProducerResources?.currentValue().discardRetryInputs()
                    for itemID in Array(initialDraftTemporaryFiles.keys) { try await retireInitialTemporaryFiles(itemID: itemID) }
                    initialDraftPendingSources.removeAll()
                    initialDraftVideoAttempts.removeAll()
                }
                try requireInitialDraft(session, generation: generation)
                try await releaseInitialProducerResources()
                initialDraftNotesRecovery = nil
                initialDraftSession = nil
                clearInitialDraftVisibleState()
            } catch {
                guard initialDraftSession === session, isDraftAccountCurrent else { return }
                offlineToastMessage = .error("Discard couldn’t finish. Your retained observation is kept; try again.")
            }
        }
    }

    func persistInitialDraftNotesWhenIdle() {
        guard let session = initialDraftSession, !isInitialDraftWorkActive,
              session.frozenPlan == nil, !session.needsPreparationAbort else { return }
        let generation = draftSession.generation
        initialDraftMutationTask = Task { @MainActor [self] in
            defer { initialDraftMutationTask = nil }
            do {
                try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: session.identity.ownerID) { [self] in
                    try requireInitialDraft(session, generation: generation)
                    try await persistInitialDraftNotes(session)
                }
            } catch {
                guard initialDraftSession === session, isDraftAccountCurrent else { return }
                offlineToastMessage = .error("Your notes are kept here, but couldn’t be saved yet. Try again before leaving.")
            }
        }
    }

    private func clearInitialDraftVisibleState() {
        retireMediaReview()
        cancelActiveCropTask()
        photoReviewCommit = nil; videoReviewCommitID = nil
        stagedCapture.clearAll(); draftOwnedFiles.removeAll()
        clearFieldNotesAfterFinalMediaRemoval()
        descriptionDraft = .init(); imageToCrop = nil; editingCropIndex = nil
        selectedPhotoItems.removeAll(); isReviewActive = false
        audioDraftOperation = nil; discardConfirmationGeneration = nil
        draftSession.reset()
    }
}
