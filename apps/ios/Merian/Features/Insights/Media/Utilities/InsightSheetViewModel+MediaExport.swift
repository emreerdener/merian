import Foundation

extension InsightSheetViewModel {
    // MARK: - Media & Share Exports

    private func exportReferenceImageUrl(for inferenceEngine: InferenceEngine) -> String? {
        guard !shouldSuppressReferenceImages,
              inferenceEngine.speciesData?.shouldSuppressReferenceImages != true else {
            return nil
        }
        return inferenceEngine.speciesData?.referenceImageUrl
    }

    func saveUserMedia(
        expectedScanId: String,
        expectedGeneration: UInt64,
        inferenceEngine: InferenceEngine
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ),
              inferenceEngine.speciesData?.scanId?
                .caseInsensitiveCompare(expectedScanId) == .orderedSame,
              !state.isSavingMedia else {
            return
        }
        state.isSavingMedia = true

        let exportMedia = activeMedia
        let liveData = exportMedia.items.compactMap { if case .liveImage(let data) = $0 { return data } else { return nil } }.first
        let imagePaths = exportMedia.items.compactMap { if case .image(let path) = $0 { return path } else { return nil } }
        let videoPaths = exportMedia.items.compactMap { if case .video(let path, _) = $0 { return path } else { return nil } }

        let request = MediaSaveRequest.make(
            liveImageData: liveData,
            imagePaths: imagePaths,
            videoPaths: videoPaths,
            referenceImageURL: exportReferenceImageUrl(for: inferenceEngine)
        )
        let taskID = UUID()
        let saveMedia = dependencies.saveMedia
        mediaSaveTask?.cancel()
        mediaSaveTaskID = taskID
        mediaSaveTask = Task { @MainActor [weak self] in
            let result = await saveMedia(request)
            guard !Task.isCancelled,
                  let self,
                  self.mediaSaveTaskID == taskID,
                  self.isPresentingLocalRecord(
                      scanId: expectedScanId,
                      generation: expectedGeneration
                  ) else {
                return
            }
            self.mediaSaveTask = nil
            self.mediaSaveTaskID = nil
            self.state.isSavingMedia = false
            self.state.lastMediaSaveResult = result
            if result.totalSaved > 0 {
                self.dependencies.successFeedback()
                self.state.showMediaSaveAlert = true
            } else {
                self.dependencies.errorFeedback()
                self.state.toastMessage = .error(
                    "No photos or videos could be saved"
                )
            }
        }
    }

    func shareDiscovery(
        expectedScanId: String,
        expectedGeneration: UInt64,
        inferenceEngine: InferenceEngine
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ),
              inferenceEngine.speciesData?.scanId?
                .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
            return
        }
        let commonName = resolvedHeaderTitle
        let scientificName = inferenceEngine.speciesData?.scientificName ?? "Awaiting taxonomy"
        let exportMedia = activeMedia
        let liveData = exportMedia.items.compactMap { if case .liveImage(let data) = $0 { return data } else { return nil } }.first
        let historicPath = exportMedia.items.compactMap { if case .image(let path) = $0 { return path } else { return nil } }.first
            ?? toolbarRecordSnapshot?.coverImagePath

        let request = DiscoveryShareRequest.make(
            commonName: commonName,
            scientificName: scientificName,
            liveImageData: liveData,
            primaryImageReference: historicPath,
            fallbackImageReference: exportReferenceImageUrl(
                for: inferenceEngine
            )
        )
        let taskID = UUID()
        let prepareMediaShare = dependencies.prepareMediaShare
        mediaShareTask?.cancel()
        mediaShareTaskID = taskID
        mediaShareTask = Task { @MainActor [weak self] in
            let payload = await prepareMediaShare(request)
            guard !Task.isCancelled,
                  let self,
                  self.mediaShareTaskID == taskID,
                  self.isPresentingLocalRecord(
                      scanId: expectedScanId,
                      generation: expectedGeneration
                  ) else {
                return
            }
            self.mediaShareTask = nil
            self.mediaShareTaskID = nil
            self.dependencies.presentMediaShare(payload)
        }
    }
}
