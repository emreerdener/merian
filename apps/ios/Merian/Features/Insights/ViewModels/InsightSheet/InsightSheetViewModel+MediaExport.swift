import Foundation

extension InsightSheetViewModel {
    // MARK: - Media & Share Exports

    func saveUserPhotos(inferenceEngine: InferenceEngine) {
        guard !state.isSavingPhotos else { return }
        state.isSavingPhotos = true

        let exportMedia = activeMedia
        let liveData = exportMedia.items.compactMap { if case .liveImage(let data) = $0 { return data } else { return nil } }.first
        let validPaths = exportMedia.items.compactMap { if case .image(let path) = $0 { return path } else { return nil } }
        let refUrls = inferenceEngine.speciesData?.referenceImageUrl

        InsightMediaExportManager.shared.saveUserPhotos(
            liveData: liveData,
            validPaths: validPaths,
            referenceImageUrl: refUrls
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
        let refUrls = inferenceEngine.speciesData?.referenceImageUrl

        InsightMediaExportManager.shared.shareDiscovery(
            commonName: commonName,
            scientificName: scientificName,
            liveData: liveData,
            historicPath: historicPath,
            referenceImageUrl: refUrls,
            presentShareSheet: { items in
                ShareSheetUtility.present(items: items)
            }
        )
    }
}
