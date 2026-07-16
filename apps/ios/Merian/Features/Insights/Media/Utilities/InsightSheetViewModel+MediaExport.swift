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

    func saveUserPhotos(inferenceEngine: InferenceEngine) {
        guard !state.isSavingPhotos else { return }
        state.isSavingPhotos = true

        let exportMedia = activeMedia
        let liveData = exportMedia.items.compactMap { if case .liveImage(let data) = $0 { return data } else { return nil } }.first
        let validPaths = exportMedia.items.compactMap { if case .image(let path) = $0 { return path } else { return nil } }

        InsightMediaExportManager.shared.saveUserPhotos(
            liveData: liveData,
            validPaths: validPaths,
            referenceImageUrl: exportReferenceImageUrl(for: inferenceEngine)
        ) { photosSaved in
            self.state.isSavingPhotos = false
            if photosSaved > 0 {
                HapticManager.shared.triggerSuccessPulse()
                self.state.showSaveSuccessAlert = true
            }
        }
    }

    func shareDiscovery(inferenceEngine: InferenceEngine) {
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
                ShareSheetUtility.present(items: items)
            }
        )
    }
}
