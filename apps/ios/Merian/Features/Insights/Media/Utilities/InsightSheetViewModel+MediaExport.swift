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

        InsightMediaExportManager.shared.saveUserMedia(
            liveData: liveData,
            imagePaths: imagePaths,
            videoPaths: videoPaths,
            referenceImageUrl: exportReferenceImageUrl(for: inferenceEngine)
        ) { result in
            guard self.isPresentingLocalRecord(
                scanId: expectedScanId,
                generation: expectedGeneration
            ) else {
                return
            }
            self.state.isSavingMedia = false
            self.state.lastMediaSaveResult = result
            if result.totalSaved > 0 {
                HapticManager.shared.triggerSuccessPulse()
                self.state.showMediaSaveAlert = true
            } else {
                HapticManager.shared.triggerErrorThump()
                self.state.toastMessage = "No photos or videos could be saved"
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

        InsightMediaExportManager.shared.shareDiscovery(
            commonName: commonName,
            scientificName: scientificName,
            liveData: liveData,
            historicPath: historicPath,
            referenceImageUrl: exportReferenceImageUrl(for: inferenceEngine),
            presentShareSheet: { items in
                guard self.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                ) else {
                    return
                }
                ShareSheetUtility.present(items: items)
            }
        )
    }
}
