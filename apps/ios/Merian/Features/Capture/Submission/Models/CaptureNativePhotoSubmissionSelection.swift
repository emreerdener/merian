import Foundation

/// Read-only assertions from native preparation. No storage or execution rights.
struct CaptureNativePhotoSubmissionSelection {
    let metadata: SharedMediaNativeAppMetadataRequest
    let pairs: [SharedMediaNativePairFileState]
    let pairIDs: [UUID]
    let identity: StagedCapture.NativePhotoDraft
    let supportingBytes: Data

    init(metadata: SharedMediaNativeAppMetadataRequest, pairs: [SharedMediaNativePairFileState]) throws {
        let package = metadata.package
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.envelope)
        guard metadata.envelope == package.envelope, package.phase == "draftOwned",
              package.tier == "pending", !package.retiring, envelope.attempt == nil,
              (1...2).contains(pairs.count), envelope.intents == pairs.map(\.plan.intent) else {
            throw SharedMediaStorageFailure.stale
        }
        let intents = try pairs.map { try $0.intent() }
        guard Set(intents.map(\.pairID)).count == pairs.count else { throw SharedMediaStorageFailure.conflict }
        for (pair, intent) in zip(pairs, intents) {
            let reference = intent.preparation.original.reference
            guard pair.phase == "ready", pair.publishedRevision != nil,
                  pair.plan.inventoryID == metadata.profile.inventoryID,
                  pair.plan.inventoryGeneration == metadata.profile.generation,
                  pair.plan.packageID == package.id, pair.plan.draftGeneration == package.generation,
                  reference.ownerID == metadata.profile.ownerID, reference.packageID == package.id,
                  reference.draftGeneration == package.generation,
                  envelope.intents.contains(pair.plan.intent) else { throw SharedMediaStorageFailure.stale }
        }
        self.metadata = metadata; self.pairs = pairs; pairIDs = intents.map(\.pairID)
        identity = .init(ownerID: metadata.profile.ownerID, packageID: package.id, draftGeneration: package.generation)
        supportingBytes = try SharedMediaNativeFrozenSupporting(contexts: envelope.contexts, presentation: envelope.presentation).encoded()
    }

    func validate(_ snapshot: CaptureNativePhotoSubmissionSnapshot) throws {
        guard snapshot.identity == identity, snapshot.supportingBytes == supportingBytes,
              snapshot.admission.audioFilePaths.isEmpty, snapshot.admission.videoFilePaths.isEmpty,
              snapshot.references.count == pairs.count,
              snapshot.admission.imageProvenance.allSatisfy({ $0 == .added }) else { throw SharedMediaStorageFailure.stale }
        for index in pairs.indices {
            let intent = try pairs[index].intent()
            guard snapshot.references[index] == intent.preparation.original.reference,
                  snapshot.admission.imageFocusRegions[index] == intent.focus,
                  snapshot.admission.imagePayloads[index].count == intent.ai.byteCount,
                  SharedMediaAcquisitionEncoding.digest(snapshot.admission.imagePayloads[index]) == intent.ai.sha256,
                  snapshot.displayPayloads[index].count == intent.display.byteCount,
                  SharedMediaAcquisitionEncoding.digest(snapshot.displayPayloads[index]) == intent.display.sha256 else {
                throw SharedMediaStorageFailure.stale
            }
        }
    }

    func validate(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws {
        try metadata.requireReceivingSelection(prepared)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        guard frozen.supportingBytes == supportingBytes,
              frozen.entries.map(\.intent) == pairs.map(\.plan.intent) else { throw SharedMediaStorageFailure.stale }
    }
}

/// Full submitted value, including presentation and display bytes omitted by
/// legacy admission. Retained across ambiguity, independent of UI lifetime.
struct CaptureNativePhotoSubmissionSnapshot: Equatable {
    let identity: StagedCapture.NativePhotoDraft
    let admission: CaptureSubmissionAdmissionSnapshot
    let references: [PhotoOriginalReference]
    let displayPayloads: [Data]
    let supportingBytes: Data

    init(_ capture: StagedCapture) throws {
        guard let identity = capture.nativePhotoDraft, (1...2).contains(capture.images.count),
              capture.audios.isEmpty, capture.videos.isEmpty else { throw SharedMediaStorageFailure.invalid }
        self.identity = identity
        admission = .init(capture)
        references = try capture.images.map {
            guard let reference = $0.photoOriginalReference else { throw SharedMediaStorageFailure.invalid }
            return reference
        }
        displayPayloads = capture.images.map(\.displayData)
        let presentation = try capture.images.map { image -> PhotoPreparationImagePresentation in
            guard let reference = image.photoOriginalReference else { throw SharedMediaStorageFailure.invalid }
            let environment = image.original.environmentContext
            return .init(referenceID: reference.referenceID, addedAt: image.addedAt,
                isFromGallery: image.original.isFromGallery, cropQuarterTurns: image.original.lastCropQuarterTurns,
                cropScale: image.original.lastCropScale, cropOffsetX: image.original.lastCropOffset.width,
                cropOffsetY: image.original.lastCropOffset.height, focus: image.focusRegion,
                latitude: environment?.location?.coordinate.latitude, longitude: environment?.location?.coordinate.longitude,
                locationName: environment?.locationName, weatherCondition: environment?.weatherCondition,
                weatherTemperature: environment?.weatherTemperature, captureDate: environment?.captureDate)
        }
        supportingBytes = try SharedMediaNativeFrozenSupporting(
            contexts: capture.observationContexts.map(\.context), presentation: presentation).encoded()
    }
}
