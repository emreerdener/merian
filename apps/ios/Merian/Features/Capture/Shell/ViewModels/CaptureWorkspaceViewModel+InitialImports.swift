import Foundation
import PhotosUI
import SwiftUI

extension CaptureWorkspaceViewModel {
    func importInitialPhotoItems(_ items: [PhotosPickerItem]) {
        guard initialDraftMutationTask == nil, let account = dependencies.submission.admission.accountID(),
              let operation = beginDraftOperation() else { return }
        let generation = draftSession.generation
        let isPro = dependencies.scan.canStartProScan()
        let selected = items.prefix(availableStagedCaptureSlots).map { (UUID(), $0) }
        selectedPhotoItems.removeAll()
        revokeAutomaticSubmission()
        initialDraftMutationTask = Task { @MainActor [self] in
            var succeeded = false
            defer {
                initialDraftMutationTask = nil
                completeDraftOperation(operation, succeeded: succeeded)
            }
            do {
                guard !selected.isEmpty,
                      await admitSelectedImageImport(imageCount: selected.count, operation: operation) else { return }
                let session = try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: account) { [self] in
                    let session = try await resolveInitialDraft()
                    try requireInitialDraft(session, generation: generation)
                    guard session.frozenPlan == nil, session.sources.allSatisfy(\.ready),
                          (session.journal?.value.items.filter { !$0.sourceIDs.isEmpty }.count ?? 0) + selected.count <= stagedCaptureLimit else {
                        throw SharedMediaStorageFailure.capacity
                    }
                    for (itemID, item) in selected {
                        let addedAt = Date()
                        let historical = await historicalContextSnapshot(for: item.itemIdentifier)
                        try requireInitialDraft(session, generation: generation)
                        guard let source = try await item.loadTransferable(type: PhotoOriginalPickerTransfer.self) else {
                            throw SharedMediaStorageFailure.unavailable
                        }
                        try requireInitialDraft(session, generation: generation)
                        let contentType = try CaptureInitialSourceAttempt.imageContentType(for: source.bytes)
                        let input = CaptureInitialSourceAttempt(itemID: itemID, bytes: source.bytes, role: .sourceImage,
                            contentType: contentType,
                            context: .init(origin: .imported, cameraVerticalCenter: nil,
                                facts: .init(addedAt: addedAt, context: historical?.makeEnvironmentContext())),
                            review: .photo(.init(format: .stillImage, isPro: isPro, cropDisplaySize: 1,
                                quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)))
                        initialDraftPendingSources.append(input)
                        try await input.retain(in: session)
                        initialDraftPendingSources.removeAll { $0.itemID == itemID && $0.role == .sourceImage }
                    }
                    try await persistInitialDraftNotes(session)
                    return session
                }
                try await refreshInitialDraftPresentation(session, generation: generation)
                selectedPhotoItems.removeAll()
                succeeded = true
            } catch {
                guard isDraftAccountCurrent, draftSession.generation == generation else { return }
                offlineToastMessage = .error("Photo import couldn’t finish. Any retained originals are kept for recovery.")
            }
        }
    }
}
