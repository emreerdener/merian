import Foundation

extension CaptureWorkspaceViewModel {
    func startInitialRecording(_ recorder: AudioCaptureManager, operation: CaptureDraftSession.Operation,
                               boostPreview: Bool) async throws {
        guard let account = dependencies.submission.admission.accountID() else { throw SharedMediaStorageFailure.closed }
        let generation = draftSession.generation
        try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: account) { [self] in
            let session = try await resolveInitialDraft()
            try requireInitialDraft(session, generation: generation)
            guard draftSession.contains(operation), let resources = try initialDraftProducerResources?.currentValue() else {
                throw SharedMediaStorageFailure.closed
            }
            try resources.retain(recorder)
            recorder.holdOriginalForDraft(recordingID: operation.id)
            try resources.preserveBeforeRetirement(itemID: operation.id,
                discard: { recorder.releaseOriginalForDraft(recordingID: operation.id) }) { [self] in
                if !initialDraftPendingSources.contains(where: { $0.itemID == operation.id }),
                   let original = try await recorder.copyHeldDraftOriginal(recordingID: operation.id) {
                    initialDraftPendingSources.append(.init(itemID: operation.id, bytes: original.bytes, role: .sourceAudio,
                        contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil,
                            facts: .init(addedAt: original.capturedAt,
                                context: EnvironmentContext(location: nil, captureDate: original.capturedAt))), review: nil))
                }
                recorder.releaseOriginalForDraft(recordingID: operation.id)
            }
            try await recorder.startRecording(recordingID: operation.id, boostRecordingPreview: boostPreview)
            try requireInitialDraft(session, generation: generation)
        }
    }

    func stageInitialRecording(from recorder: AudioCaptureManager, expectedPath: String,
                               operation: CaptureDraftSession.Operation) {
        guard initialDraftMutationTask == nil, let account = dependencies.submission.admission.accountID(),
              let capturedAt = recorder.recordingStartedAt else { return }
        let generation = draftSession.generation
        let facts = SharedMediaCaptureSourceFacts(addedAt: capturedAt,
            context: EnvironmentContext(location: nil, captureDate: capturedAt))
        initialDraftMutationTask = Task { @MainActor [self] in
            var succeeded = false
            defer {
                initialDraftMutationTask = nil
                if succeeded {
                    audioDraftOperation = nil
                    completeDraftOperation(operation, succeeded: true)
                }
            }
            do {
                let session = try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: account) { [self] in
                    let session = try await resolveInitialDraft()
                    try requireInitialDraft(session, generation: generation)
                    guard let resources = try initialDraftProducerResources?.currentValue() else { throw SharedMediaStorageFailure.closed }
                    try resources.retain(recorder)
                    let existingItem = session.sources.contains { $0.itemID == operation.id }
                    guard session.frozenPlan == nil,
                          session.sources.allSatisfy({ $0.ready || $0.itemID == operation.id }),
                          existingItem || (session.journal?.value.items.filter { !$0.sourceIDs.isEmpty }.count ?? 0) < stagedCaptureLimit else {
                        throw SharedMediaStorageFailure.capacity
                    }
                    try await recorder.withSubmittedOriginal(recordingID: operation.id, path: expectedPath) { url in
                        let existing = initialDraftPendingSources.first { $0.itemID == operation.id && $0.role == .sourceAudio }
                        let input: CaptureInitialSourceAttempt
                        if let existing { input = existing } else {
                            let bytes = try await CaptureInitialSourceReader().read(url, maximumBytes: 2_700_000)
                            input = .init(itemID: operation.id, bytes: bytes, role: .sourceAudio,
                                contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil, facts: facts),
                                review: nil)
                            initialDraftPendingSources.append(input)
                        }
                        try requireInitialDraft(session, generation: generation)
                        try await input.retain(in: session)
                        try requireInitialDraft(session, generation: generation)
                    }
                    initialDraftPendingSources.removeAll { $0.itemID == operation.id && $0.role == .sourceAudio }
                    try await persistInitialDraftNotes(session)
                    resources.acknowledge(itemID: operation.id)
                    recorder.acknowledgeRetainedOriginal(recordingID: operation.id, path: expectedPath)
                    // Custody is complete even if rendering its disposable
                    // preview fails. Do not leave a finished recorder operation
                    // blocking recovery of the durable journal.
                    succeeded = true
                    return session
                }
                try await refreshInitialDraftPresentation(session, generation: generation)
            } catch {
                guard isDraftAccountCurrent, draftSession.generation == generation else { return }
                if recorder.recordingID == operation.id { recorder.restoreSubmissionForReview() }
                offlineToastMessage = .error("The recording is retained. It couldn’t finish staging; try again.")
            }
        }
    }
}
