import Messages
import SwiftUI
import UIKit

final class MessagesViewController: MSMessagesAppViewController {
    private var hostingController: UIHostingController<MessageScanLibraryExtensionView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUIView()
    }

    private func installSwiftUIView() {
        let rootView = MessageScanLibraryExtensionView(
            onInsertScan: { [weak self] record, imageURL, completion in
                guard let self else {
                    completion(.failure(MessagesInsertionError.noActiveConversation))
                    return
                }
                self.insertScan(for: record, imageURL: imageURL, completion: completion)
            },
            onOpenMerian: { [weak self] url in
                self?.extensionContext?.open(url, completionHandler: nil)
            },
            onClose: { [weak self] in
                self?.closeExtension()
            },
            onRequestExpandedPresentation: { [weak self] in
                self?.requestPresentationStyle(.expanded)
            }
        )

        let controller = UIHostingController(rootView: rootView)
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        hostingController = controller
    }

    private func insertScan(
        for record: MessageScanShareCacheRecord,
        imageURL: URL?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let activeConversation else {
            completion(.failure(MessagesInsertionError.noActiveConversation))
            return
        }

        guard let imageURL else {
            insertText(for: record, in: activeConversation, completion: completion)
            return
        }

        activeConversation.insertAttachment(
            imageURL,
            withAlternateFilename: messageImageFilename(for: record, imageURL: imageURL)
        ) { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }

            self?.insertText(for: record, in: activeConversation, completion: completion)
        }
    }

    private func closeExtension() {
        minimizeLibrarySheet(completeRequest: true)
    }

    private func minimizeLibrarySheet(completeRequest: Bool = false) {
        view.endEditing(true)
        requestPresentationStyle(.compact)
        dismiss(animated: true)

        if completeRequest {
            DispatchQueue.main.async { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    private func insertText(
        for record: MessageScanShareCacheRecord,
        in conversation: MSConversation,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        conversation.insertText(MessageScanShareTextBuilder.descriptionText(for: record)) { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }

            completion(.success(()))
            self?.minimizeLibrarySheet()
        }
    }

    private func messageImageFilename(for record: MessageScanShareCacheRecord, imageURL: URL) -> String {
        let normalizedName = record.commonName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let basename = normalizedName.isEmpty ? "Merian-scan" : normalizedName
        let pathExtension = imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension
        return "\(basename).\(pathExtension)"
    }
}

private enum MessagesInsertionError: LocalizedError {
    case noActiveConversation

    var errorDescription: String? {
        switch self {
        case .noActiveConversation:
            return "No active Messages conversation was available."
        }
    }
}
