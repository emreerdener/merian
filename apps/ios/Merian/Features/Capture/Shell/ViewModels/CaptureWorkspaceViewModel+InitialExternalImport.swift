import Foundation

extension CaptureWorkspaceViewModel {
    func importInitialExternalImage(_ item: PendingExternalImageImport) async -> ExternalImageImportAttemptResult {
        guard !isDraftMutationLocked, let account = dependencies.submission.admission.accountID(),
              await requestImageImportEntryAdmission(prospectiveImageCount: 1),
              let operation = beginDraftOperation() else { return .temporarilyBlocked }
        let generation = draftSession.generation
        let imports = dependencies.externalImageImports
        var outcome = ExternalImageImportAttemptResult.temporarilyBlocked
        let work = Task { @MainActor [self] in
            var succeeded = false
            defer { initialDraftMutationTask = nil; completeDraftOperation(operation, succeeded: succeeded) }
            do {
                let session = try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: account) { [self] in
                    let session = try await resolveInitialDraft()
                    try requireInitialDraft(session, generation: generation)
                    guard session.frozenPlan == nil, session.sources.allSatisfy(\.ready) else { throw SharedMediaStorageFailure.closed }
                    if !session.sources.contains(where: { $0.itemID == item.id }) {
                        guard (session.journal?.value.items.filter { !$0.sourceIDs.isEmpty }.count ?? 0) < stagedCaptureLimit,
                              let url = await imports.fileURL(for: item) else { throw SharedMediaStorageFailure.capacity }
                        let bytes = try await CaptureInitialSourceReader().read(url, maximumBytes: PhotoPreparationPolicy.original)
                        let contentType = try CaptureInitialSourceAttempt.imageContentType(for: bytes)
                        let metadata = try await DetachedWork.value(priority: .userInitiated, category: .imagePreparation) {
                            ImportedImageMetadataExtractor.extract(from: url)
                        }
                        let historical = await historicalContextSnapshot(for: metadata)
                        try requireInitialDraft(session, generation: generation)
                        let input = CaptureInitialSourceAttempt(itemID: item.id, bytes: bytes, role: .sourceImage,
                            contentType: contentType, context: .init(origin: .imported, cameraVerticalCenter: nil,
                                facts: .init(addedAt: item.receivedAt, context: historical?.makeEnvironmentContext())),
                            review: .photo(.init(format: .stillImage, isPro: dependencies.scan.canStartProScan(),
                                cropDisplaySize: 1, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)))
                        initialDraftPendingSources.append(input)
                        try await input.retain(in: session)
                        initialDraftPendingSources.removeAll { $0.itemID == item.id }
                    }
                    try await persistInitialDraftNotes(session)
                    try await retireInitialInboxCopies(session, generation: generation)
                    return session
                }
                try await refreshInitialDraftPresentation(session, generation: generation)
                succeeded = true
                outcome = .staged
                operationState.clearExternalImportPresentationHistory(for: item.id)
            } catch {
                guard isDraftAccountCurrent, draftSession.generation == generation else { return }
                offlineToastMessage = .error("The shared photo is kept. Import couldn’t finish; try again.")
            }
        }
        initialDraftMutationTask = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        return outcome
    }

    /// The inbox keeps ownership until the matching journal source is ready.
    /// Stable item identity also recognizes a cold retry after lost UI delivery.
    func retireInitialInboxCopies(_ session: CaptureInitialDraftSession, generation: UUID) async throws {
        let imports = dependencies.externalImageImports
        for item in await imports.pendingImports() {
            guard let source = session.sources.first(where: { $0.itemID == item.id && $0.ready && $0.input.role == .sourceImage }) else { continue }
            try requireInitialDraft(session, generation: generation)
            try await imports.retireVerified(item, byteCount: source.input.byteCount, sha256: source.input.sha256)
            try requireInitialDraft(session, generation: generation)
        }
    }
}
