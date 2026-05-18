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
            onInsertImage: { [weak self] record, attachmentURL in
                self?.insertImage(for: record, attachmentURL: attachmentURL)
            },
            onInsertCard: { [weak self] record, thumbnailURL in
                self?.insertCard(for: record, thumbnailURL: thumbnailURL)
            },
            onInsertDescription: { [weak self] record, includeFieldNotes in
                self?.insertDescription(for: record, includeFieldNotes: includeFieldNotes)
            },
            onOpenMerian: { [weak self] url in
                self?.extensionContext?.open(url, completionHandler: nil)
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

    private func insertImage(
        for record: MessageScanShareCacheRecord,
        attachmentURL: URL
    ) {
        let fallbackName = "\(record.commonName)-Merian.jpg"
        activeConversation?.insertAttachment(
            attachmentURL,
            withAlternateFilename: fallbackName,
            completionHandler: nil
        )
    }

    private func insertCard(
        for record: MessageScanShareCacheRecord,
        thumbnailURL: URL?
    ) {
        let layout = MSMessageTemplateLayout()
        layout.caption = record.commonName
        layout.subcaption = record.scientificName
        layout.trailingSubcaption = MessageScanShareTextBuilder.cardCaption(for: record)

        if let thumbnailURL,
           let image = UIImage(contentsOfFile: thumbnailURL.path) {
            layout.image = image
        }

        let message = MSMessage()
        message.layout = layout
        message.url = record.cardURL
        activeConversation?.insert(message, completionHandler: nil)
    }

    private func insertDescription(
        for record: MessageScanShareCacheRecord,
        includeFieldNotes: Bool
    ) {
        let text = MessageScanShareTextBuilder.descriptionText(
            for: record,
            includeFieldNotes: includeFieldNotes
        )
        activeConversation?.insertText(text, completionHandler: nil)
    }
}
