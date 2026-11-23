import Foundation

extension CaptureWorkspaceViewModel {
    /// Uses the same qualified installation as History. Existing legacy and
    /// photo-only test compositions keep their explicit owners until resolved.
    var usesInitialDraftComposition: Bool {
        initialDraftSession != nil || (PreparedHistoryReanalysisComposition.isAppInstallationQualified
            && reanalysisEditor == nil && baseRefinementContext == nil
            && dependencies.photoOriginalPreparation == nil && !usesNativePhotoComposition)
    }

    func requireInitialDraft(_ session: CaptureInitialDraftSession, generation: UUID) throws {
        guard !Task.isCancelled, initialDraftSession === session,
              draftSession.generation == generation, isDraftAccountCurrent,
              dependencies.submission.admission.accountID() == session.identity.ownerID,
              !dependencies.submission.admission.isLibraryAccessBlocked() else {
            throw SharedMediaStorageFailure.closed
        }
    }

    /// Called inside the registered producer work, before loading source bytes.
    /// Reopening can discover a saved draft; it must never silently merge that
    /// draft with a legacy staging buffer or another account's presentation.
    func resolveInitialDraft() async throws -> CaptureInitialDraftSession {
        guard usesInitialDraftComposition, let account = dependencies.submission.admission.accountID(),
              isDraftAccountCurrent, !dependencies.submission.admission.isLibraryAccessBlocked() else {
            throw SharedMediaStorageFailure.closed
        }
        if let initialDraftSession {
            try requireInitialDraft(initialDraftSession, generation: draftSession.generation)
            return initialDraftSession
        }
        guard stagedCapture.physicalItemCount == 0 else { throw SharedMediaStorageFailure.conflict }
        let generation = draftSession.generation
        let authGeneration = diContainer.supabaseManager.authSessionGeneration
        if initialDraftProducerResources == nil {
            initialDraftProducerResources = try await diContainer.nativeMediaLifecycle.captureDraftProducerResources(ownerID: account)
        }
        let session = try await CaptureInitialDraftSession.app(ownerID: account, diContainer: diContainer)
        guard draftSession.generation == generation, isDraftAccountCurrent,
              diContainer.supabaseManager.authSessionGeneration == authGeneration,
              dependencies.submission.admission.accountID() == account else { throw SharedMediaStorageFailure.closed }
        initialDraftSession = session
        if stagedCapture.isEmpty, let journal = session.journal {
            stagedCapture.observationContexts = journal.value.items.compactMap {
                guard case let .description(id, text) = $0 else { return nil }
                return .init(context: ObservationContext(freeText: text), id: id)
            }
            descriptionDraft = .init(freeText: stagedCapture.observationContexts.map { $0.context.freeText }.joined(separator: "\n\n"))
        }
        initialDraftOwnerID = account
        initialDraftAuthGeneration = authGeneration
        return session
    }

    /// The old presentation remains a cleanup liability until its owner joins
    /// every mounted preview and acknowledges exact disposable-file retirement.
    func releaseInitialDraftPresentation() async throws {
        guard let retained = initialDraftPresentation else { return }
        guard await retained.release() else { throw SharedMediaStorageFailure.unavailable }
        initialDraftPresentation = nil
    }

    func releaseInitialProducerResources() async throws {
        guard let retained = initialDraftProducerResources else { return }
        guard await retained.release() else { throw SharedMediaStorageFailure.unavailable }
        initialDraftProducerResources = nil
    }

    func refreshInitialDraftPresentation(_ session: CaptureInitialDraftSession, generation: UUID) async throws {
        try requireInitialDraft(session, generation: generation)
        try await releaseInitialDraftPresentation()
        let retained = try await diContainer.nativeMediaLifecycle.captureDraftPresentation(session: session)
        // Keep the cleanup handle before any subsequent validation can fail.
        initialDraftPresentation = retained
        try requireInitialDraft(session, generation: generation)
        let presentation = try retained.currentValue()
        stagedCapture = presentation.capture
        draftOwnedFiles = [] // Only the retained presentation may retire its files.
        descriptionDraft = .init(freeText: presentation.capture.observationContexts.map { $0.context.freeText }.joined(separator: "\n\n"))
        isReviewActive = stagedCapture.physicalItemCount > 0
    }

    /// Persist the visible description with stable identity. Physical membership
    /// and preparation recipes come from the retained journal, never previews.
    func persistInitialDraftNotes(_ session: CaptureInitialDraftSession) async throws {
        guard session.frozenPlan == nil else { return }
        guard let journal = session.journal else { return }
        guard journal.value.phase == .editing else { return }
        let media = journal.value.items.filter { if case .description = $0 { return false }; return true }
        let notes = stagedCapture.observationContexts.map { SharedMediaCaptureDraftJournal.Item.description(id: $0.id, text: $0.context.freeText) }
        try await session.updateReview(items: media + notes)
    }

    func submitInitialDraft(preferredGoal: FieldTripPreferredGoal?) async {
        guard let session = initialDraftSession, canSubmitDraft, isDraftAccountCurrent,
              !dependencies.submission.admission.isLibraryAccessBlocked() else { return }
        let generation = draftSession.generation
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }
        do {
            try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: session.identity.ownerID) { [self] in
                try requireInitialDraft(session, generation: generation)
                if session.frozenPlan == nil { try await recoverInitialDraftSources(session, generation: generation) }
                try await retireInitialInboxCopies(session, generation: generation)
                try await persistInitialDraftNotes(session)
                if session.frozenPlan == nil { _ = try await session.prepareReview() }
                try requireInitialDraft(session, generation: generation)
                // Choose the first physical item's immutable shutter/import
                // facts. Unknown time is represented by its original addedAt,
                // never the time a pending submission is retried.
                guard let journal = session.journal,
                      let primary = journal.value.items.first(where: { !$0.sourceIDs.isEmpty }),
                      let sourceID = primary.sourceIDs.first,
                      let source = journal.value.sources.first(where: { $0.input.id == sourceID }),
                      let facts = source.input.context.facts else { throw SharedMediaStorageFailure.conflict }
                let goal = CaptureSubmissionPolicy.preferredGoal(preferredGoal,
                    hasCameraStill: journal.value.sources.contains { $0.input.role == .sourceImage && $0.input.context.origin == .camera },
                    hasGalleryStill: journal.value.sources.contains { $0.input.role == .sourceImage && $0.input.context.origin == .imported },
                    hasAudio: journal.value.sources.contains { $0.input.role == .sourceAudio || $0.input.role == .sourceCompanionAudio },
                    hasVideo: journal.value.sources.contains { $0.input.role == .sourceVideo })
                _ = try await session.submit(using: .live(queue: diContainer.offlineQueueManager)) { plan, funding in
                    try .init(plan: plan, funding: funding, timestamp: facts.captureDate ?? facts.addedAt,
                        telemetry: facts.telemetry, blurScore: nil, preferredGoal: goal)
                }
            }
            try requireInitialDraft(session, generation: generation)
            try await releaseInitialDraftPresentation()
            try await releaseInitialProducerResources()
            // Acceptance, not presentation dismissal, authorizes clearing this
            // editor. The completed-History worker owns originals from here.
            retireMediaReview()
            stagedCapture.clearAll(); draftOwnedFiles.removeAll()
            clearFieldNotesAfterFinalMediaRemoval()
            descriptionDraft = .init(); imageToCrop = nil; editingCropIndex = nil
            isReviewActive = false; initialDraftSession = nil
            initialDraftNotesRecovery = nil
            draftSession.reset()
            offlineToastMessage = .information("Your identification request was saved.")
        } catch {
            guard initialDraftSession === session, isDraftAccountCurrent else { return }
            offlineToastMessage = .error("Your observation is retained. Identification couldn’t finish; try again.")
        }
    }
}
