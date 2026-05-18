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

    func configure(
        extensionContext: NSExtensionContext?,
        complete: @escaping () -> Void,
        cancel: @escaping (Error) -> Void
    ) {
        self.extensionContext = extensionContext
        self.complete = complete
        self.cancel = cancel

        Task {
            await loadSharedImage()
        }
    }

    func startUpload() {
        guard !didStartUpload, let preparedImage else { return }

        let settings = ShareImportSharedSettingsStore.load()
        guard settings.canPerformScan else {
            state = .failure("Open Merian to continue identifying images.")
            return
        }

        didStartUpload = true
        state = .uploading

        Task {
            do {
                let scanId = try await ShareImportNetworkClient().uploadAndQueue(preparedImage)
                ShareImportSharedSettingsStore.consumeSharedFreeScanIfNeeded()
                ShareImportReceiptStore.upsert(
                    ShareImportReceipt(scanId: scanId, createdAt: Date(), status: .queued)
                )
                state = .success
                try? await Task.sleep(nanoseconds: 900_000_000)
                complete?()
            } catch {
                didStartUpload = false
                state = .failure(error.localizedDescription)
            }
        }
    }

    func retry() {
        startUpload()
    }

    func cancelRequest() {
        cancel?(ShareImportItemProviderError.loadFailed)
    }

    private func loadSharedImage() async {
        do {
            guard let provider = ShareImportItemProviderResolver.firstImageProvider(in: extensionContext) else {
                throw ShareImportItemProviderError.noImage
            }

            let fileURL = try await ShareImportItemProviderResolver.loadImageFile(from: provider)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let preparedImage = try ShareImportImagePreparer.prepare(fileURL: fileURL)

            self.preparedImage = preparedImage
            self.previewImage = preparedImage.previewImage

            let settings = ShareImportSharedSettingsStore.load()
            self.requiresConfirmation = settings.requiresScanConfirmation
            self.state = .ready

            if !settings.requiresScanConfirmation {
                startUpload()
            }
        } catch {
            state = .failure(error.localizedDescription)
        }
    }
}
