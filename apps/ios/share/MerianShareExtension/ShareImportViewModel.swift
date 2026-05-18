import Foundation
import SwiftUI
import UIKit

@MainActor
final class ShareImportViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case uploading
        case success
        case failure(String)
    }

    @Published var state: State = .loading
    @Published var previewImage: UIImage?
    @Published var requiresConfirmation = false

    private var preparedImage: ShareImportPreparedImage?
    private var extensionContext: NSExtensionContext?
    private var complete: (() -> Void)?
    private var cancel: ((Error) -> Void)?
    private var didStartUpload = false
    private var finishTask: Task<Void, Never>?

    func configure(
        extensionContext: NSExtensionContext?,
        complete: @escaping () -> Void,
        cancel: @escaping (Error) -> Void
    ) {
        self.extensionContext = extensionContext
        self.complete = complete
        self.cancel = cancel

        ShareImportLog.logger.debug("ShareImportViewModel.configure: extension configured")
        Task {
            await loadSharedImage()
        }
    }

    func startUpload() {
        guard !didStartUpload, let preparedImage else {
            ShareImportLog.logger.debug("ShareImportViewModel.startUpload: ignored didStart=\(self.didStartUpload, privacy: .public) hasPrepared=\((self.preparedImage != nil), privacy: .public)")
            return
        }

        let settings = ShareImportSharedSettingsStore.load()
        guard settings.canPerformScan else {
            ShareImportLog.logger.debug("ShareImportViewModel.startUpload: blocked by shared scan settings")
            state = .failure("Open Merian to continue identifying images.")
            return
        }

        didStartUpload = true
        state = .uploading
        ShareImportLog.logger.debug("ShareImportViewModel.startUpload: queue handoff started scanId=\(preparedImage.scanId, privacy: .public) bytes=\(preparedImage.imageData.count, privacy: .public)")

        Task {
            do {
                guard let localImageFilename = ShareImportReceiptStore.writeLocalImage(
                    data: preparedImage.imageData,
                    scanId: preparedImage.scanId,
                    fileExtension: preparedImage.fileExtension
                ) else {
                    throw ShareImportHandoffError.writeFailed
                }

                let receipt = ShareImportReceipt(
                    scanId: preparedImage.scanId,
                    createdAt: Date(),
                    status: .queued,
                    localImageFilename: localImageFilename,
                    imageContentType: preparedImage.contentType,
                    capturedAt: preparedImage.telemetry.timestamp,
                    gpsLatitude: preparedImage.telemetry.gpsLatitude,
                    gpsLongitude: preparedImage.telemetry.gpsLongitude,
                    gpsElevation: preparedImage.telemetry.gpsElevation
                )
                guard ShareImportReceiptStore.upsert(receipt),
                      ShareImportReceiptStore.containsQueuedReceipt(scanId: preparedImage.scanId) else {
                    throw ShareImportHandoffError.writeFailed
                }

                ShareImportLog.logger.debug("ShareImportViewModel.startUpload: receipt queued scanId=\(preparedImage.scanId, privacy: .public) file=\(localImageFilename, privacy: .public)")
                state = .success
                scheduleFinish()
            } catch {
                didStartUpload = false
                ShareImportLog.logger.error("ShareImportViewModel.startUpload: failed scanId=\(preparedImage.scanId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                state = .failure(error.localizedDescription)
            }
        }
    }

    func retry() {
        startUpload()
    }

    func cancelRequest() {
        finishTask?.cancel()
        cancel?(ShareImportItemProviderError.loadFailed)
    }

    func finish() {
        finishTask?.cancel()
        complete?()
    }

    private func scheduleFinish() {
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                ShareImportLog.logger.debug("ShareImportViewModel.scheduleFinish: completing extension after confirmation")
                self?.complete?()
            }
        }
    }

    private func loadSharedImage() async {
        do {
            ShareImportLog.logger.debug("ShareImportViewModel.loadSharedImage: resolving provider")
            guard let provider = ShareImportItemProviderResolver.firstImageProvider(in: extensionContext) else {
                throw ShareImportItemProviderError.noImage
            }

            let fileURL = try await ShareImportItemProviderResolver.loadImageFile(from: provider)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let preparedImage = try ShareImportImagePreparer.prepare(fileURL: fileURL)

            self.preparedImage = preparedImage
            self.previewImage = preparedImage.previewImage
            ShareImportLog.logger.debug("ShareImportViewModel.loadSharedImage: prepared scanId=\(preparedImage.scanId, privacy: .public) bytes=\(preparedImage.imageData.count, privacy: .public) ext=\(preparedImage.fileExtension, privacy: .public)")

            let settings = ShareImportSharedSettingsStore.load()
            self.requiresConfirmation = settings.requiresScanConfirmation
            self.state = .ready
            ShareImportLog.logger.debug("ShareImportViewModel.loadSharedImage: ready requiresConfirmation=\(settings.requiresScanConfirmation, privacy: .public) canPerformScan=\(settings.canPerformScan, privacy: .public)")

            if !settings.requiresScanConfirmation {
                startUpload()
            }
        } catch {
            ShareImportLog.logger.error("ShareImportViewModel.loadSharedImage: failed error=\(error.localizedDescription, privacy: .public)")
            state = .failure(error.localizedDescription)
        }
    }
}

private enum ShareImportHandoffError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "Merian could not queue that image. Open Merian and try again."
    }
}
