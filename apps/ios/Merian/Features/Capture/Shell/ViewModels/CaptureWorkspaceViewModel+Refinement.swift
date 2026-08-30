import Foundation

private struct HistoricalRefinementMediaPlan: Sendable {
    let imageReferences: [StoredMediaReference]
    let fallbackAudioReferences: [StoredMediaReference]
    let fallbackDescription: ObservationContext?
    let scanId: String
    let isPro: Bool
}

extension CaptureWorkspaceViewModel {
    @discardableResult
    func startRefinementScan(
        from record: LocalScanRecord,
        initialDescription: String? = nil,
        entryPoint: RefinementEntryPoint = .standard
    ) -> Bool {
        guard diContainer.revenueCatManager.canStartProScan else {
            AppTelemetry.trackPaywallImpression()
            activeSheet = .paywall
            return true
        }
        guard canStartRefinement(from: record, entryPoint: entryPoint) else {
            MerianLog.general.debug("Blocked refinement entry point for incompatible scan state.")
            return false
        }

        startRefinementScan(
            with: RefinementScanContext(record: record, entryPoint: entryPoint),
            initialDescription: initialDescription
        )
        return true
    }

    @discardableResult
    func startRefinementScan(
        scanId: String,
        initialDescription: String? = nil,
        entryPoint: RefinementEntryPoint = .standard
    ) -> Bool {
        guard let record = fetchLocalScan(scanId: scanId) else { return false }
        return startRefinementScan(
            from: record,
            initialDescription: initialDescription,
            entryPoint: entryPoint
        )
    }

    private func canStartRefinement(from record: LocalScanRecord, entryPoint: RefinementEntryPoint) -> Bool {
        switch entryPoint {
        case .standard:
            true
        case .nonBiologicalCorrection:
            !record.isBiological
        }
    }

    private func startRefinementScan(with context: RefinementScanContext, initialDescription: String? = nil) {
        self.refinementSubjectId = context.subjectId
        self.baseRefinementContext = context
        let trimmedDescription = initialDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.refinementInitialDescriptionDraft = context.entryPoint == .nonBiologicalCorrection
            ? nil
            : (trimmedDescription?.isEmpty == false ? trimmedDescription : nil)
        self.activeSheet = nil
        self.requestedCaptureMode = .describe

        stageHistoricalMediaForRefinement(from: context)
    }

    private func stageHistoricalMediaForRefinement(from context: RefinementScanContext) {
        operationState.cancelRefinementStagingTask()
        isStagingRefinement = false

        var imageReferences = context.capturedMediaSnapshot.imageReferences
        if let fallbackImagePath = context.coverImagePath?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
           !fallbackImagePath.isEmpty {
            imageReferences.append(
                StoredMediaReference(legacyPath: fallbackImagePath)
            )
        }

        let fallbackDescription = context.capturedMediaSnapshot
            .observationContexts
            .first(where: { !$0.isEmpty })
        let fallbackAudioReferences = context.capturedMediaSnapshot
            .refinementAudioReferences
        if stageHistoricalImagesForRefinement(
            imageReferences,
            fallbackAudioReferences: fallbackAudioReferences,
            fallbackDescription: fallbackDescription,
            scanId: context.scanId
        ) {
            return
        }

        if stageHistoricalAudioForRefinement(
            fallbackAudioReferences,
            fallbackDescription: fallbackDescription,
            scanId: context.scanId
        ) {
            return
        }

        if let descriptionContext = fallbackDescription,
           stageHistoricalDescriptionForRefinement(descriptionContext) {
            isStagingRefinement = false
            return
        }
    }

    @discardableResult
    private func stageHistoricalAudioForRefinement(
        _ audioReferences: [StoredMediaReference],
        fallbackDescription: ObservationContext?,
        scanId: String
    ) -> Bool {
        guard !audioReferences.isEmpty,
              stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else {
            return false
        }

        isStagingRefinement = true
        let loader = dependencies.prepareHistoricalAudio
        let task = DetachedWork.fireAndForget(
            priority: .userInitiated,
            category: .audioPreparation
        ) { [weak self, audioReferences, fallbackDescription, scanId, loader] in
            var preparedURL: URL?
            do {
                for reference in audioReferences {
                    try Task.checkCancellation()
                    do {
                        if let candidate = try await loader(reference) {
                            guard Self.isOwnedPreparedHistoricalAudioSidecar(
                                candidate
                            ),
                                InferenceAudioPreparer.isCanonicalPreparedWAV(
                                    at: candidate
                                ) else {
                                Self.removePreparedHistoricalAudioSidecarIfOwned(
                                    candidate
                                )
                                continue
                            }
                            preparedURL = candidate
                            break
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        continue
                    }
                }

                try Task.checkCancellation()
                guard let self else {
                    if let preparedURL {
                        Self.removePreparedHistoricalAudioSidecarIfOwned(
                            preparedURL
                        )
                    }
                    return
                }

                guard let preparedURL else {
                    await MainActor.run {
                        guard self.baseRefinementContext?.scanId == scanId else { return }
                        if let fallbackDescription,
                           self.stagedCapture.availableSlots(limit: self.stagedCaptureLimit) > 0 {
                            self.stagedCapture.observationContexts.append(
                                StagedObservationContext(context: fallbackDescription)
                            )
                        } else {
                            self.offlineToastMessage = .error(
                                "The original audio is unavailable for reanalysis."
                            )
                        }
                        self.isStagingRefinement = false
                    }
                    return
                }

                let didStage = await MainActor.run { () -> Bool in
                    guard self.baseRefinementContext?.scanId == scanId,
                          self.stagedCapture.availableSlots(limit: self.stagedCaptureLimit) > 0 else {
                        return false
                    }
                    self.stagedCapture.audios.append(
                        StagedAudio(filePath: preparedURL.lastPathComponent)
                    )
                    self.isStagingRefinement = false
                    return true
                }
                if !didStage {
                    Self.removePreparedHistoricalAudioSidecarIfOwned(
                        preparedURL
                    )
                    await MainActor.run {
                        guard self.baseRefinementContext?.scanId == scanId else { return }
                        self.isStagingRefinement = false
                    }
                }
            } catch is CancellationError {
                if let preparedURL {
                    Self.removePreparedHistoricalAudioSidecarIfOwned(
                        preparedURL
                    )
                }
            } catch {
                if let preparedURL {
                    Self.removePreparedHistoricalAudioSidecarIfOwned(
                        preparedURL
                    )
                }
                guard let self else { return }
                await MainActor.run {
                    guard self.baseRefinementContext?.scanId == scanId else { return }
                    self.isStagingRefinement = false
                    self.offlineToastMessage = .error(
                        "Unable to prepare the original audio. Please try again."
                    )
                }
            }
        }
        operationState.setRefinementStagingTask(task)
        return true
    }

    @discardableResult
    private func stageHistoricalDescriptionForRefinement(_ descriptionContext: ObservationContext) -> Bool {
        guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return false }
        stagedCapture.observationContexts.append(StagedObservationContext(context: descriptionContext))
        return true
    }

    @discardableResult
    private func stageHistoricalImagesForRefinement(
        _ imageReferences: [StoredMediaReference],
        fallbackAudioReferences: [StoredMediaReference],
        fallbackDescription: ObservationContext?,
        scanId: String
    ) -> Bool {
        guard !imageReferences.isEmpty,
              stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else {
            return false
        }

        isStagingRefinement = true

        let isPro = diContainer.revenueCatManager.canStartProScan
        let loader = dependencies.prepareImage
        let downloadImage = dependencies.downloadRefinementImage
        let plan = HistoricalRefinementMediaPlan(
            imageReferences: imageReferences,
            fallbackAudioReferences: fallbackAudioReferences,
            fallbackDescription: fallbackDescription,
            scanId: scanId,
            isPro: isPro
        )

        let task = DetachedWork.fireAndForget(
            priority: .userInitiated,
            category: .imagePreparation
        ) { [weak self, plan, loader, downloadImage] in
            for imageReference in plan.imageReferences {
                do {
                    try Task.checkCancellation()
                    guard let sourceURL = imageReference.resolvedURL else {
                        continue
                    }

                    var temporaryDownloadURL: URL?
                    defer {
                        if let temporaryDownloadURL {
                            try? FileManager.default.removeItem(
                                at: temporaryDownloadURL
                            )
                        }
                    }
                    let fileURL: URL
                    if imageReference.isRemote {
                        guard let downloadedURL = try await downloadImage(
                            sourceURL
                        ) else {
                            continue
                        }
                        temporaryDownloadURL = downloadedURL
                        fileURL = downloadedURL
                    } else if FileManager.default.fileExists(atPath: sourceURL.path) {
                        fileURL = sourceURL
                    } else {
                        continue
                    }

                    try Task.checkCancellation()
                    let preparedRefinement: PreparedStagedImage?
                    do {
                        preparedRefinement = try await loader(
                            PreparedStagedImageRequest(
                                fileURL: fileURL,
                                isPro: plan.isPro,
                                historicalContext: nil
                            )
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        preparedRefinement = nil
                    }
                    guard let preparedRefinement else { continue }

                    try Task.checkCancellation()
                    guard let self else { return }
                    let didCommit = await MainActor.run { () -> Bool in
                        guard self.baseRefinementContext?.scanId == plan.scanId,
                              self.stagedCapture.availableSlots(
                                limit: self.stagedCaptureLimit
                              ) > 0 else {
                            return false
                        }
                        self.commitPreparedStagedImages([preparedRefinement])
                        self.isStagingRefinement = false
                        return true
                    }
                    if didCommit { return }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    MerianLog.general.error(
                        "Failed to prepare one historical refinement image: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }

            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.baseRefinementContext?.scanId == plan.scanId else {
                    return
                }
                if self.stageHistoricalAudioForRefinement(
                    plan.fallbackAudioReferences,
                    fallbackDescription: plan.fallbackDescription,
                    scanId: plan.scanId
                ) {
                    return
                }
                if let fallbackDescription = plan.fallbackDescription,
                   self.stageHistoricalDescriptionForRefinement(
                       fallbackDescription
                   ) {
                    self.isStagingRefinement = false
                    return
                }
                self.isStagingRefinement = false
                self.offlineToastMessage = .error(
                    "The original media is unavailable for reanalysis."
                )
            }
        }
        operationState.setRefinementStagingTask(task)
        return true
    }

    private nonisolated static func isOwnedPreparedHistoricalAudioSidecar(
        _ url: URL
    ) -> Bool {
        let standardizedURL = url.standardizedFileURL
        return standardizedURL.deletingLastPathComponent() ==
                URL.documentsDirectory.standardizedFileURL
            && standardizedURL.lastPathComponent.hasPrefix(
                "historical-refinement-"
            )
            && standardizedURL.pathExtension.lowercased() == "wav"
    }

    private nonisolated static func removePreparedHistoricalAudioSidecarIfOwned(
        _ url: URL
    ) {
        guard isOwnedPreparedHistoricalAudioSidecar(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func restoreRefinementInsightAfterCancellation() -> Bool {
        guard let scanId = baseRefinementContext?.scanId,
              let record = fetchLocalScan(scanId: scanId) else {
            return false
        }
        diContainer.inferenceEngine.load(from: record)
        activeSheet = .insight
        return true
    }

    func cancelRefinementStaging() {
        operationState.cancelRefinementStagingTask()
        isStagingRefinement = false
        baseRefinementContext = nil
        refinementInitialDescriptionDraft = nil
        refinementSubjectId = nil
    }

}
