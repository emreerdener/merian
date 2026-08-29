import SwiftData
import SwiftUI

enum CollectionAlertAction: Equatable {
    case rename
    case delete
    case create
}

struct CollectionActionAlertModifier: ViewModifier {
    let action: CollectionAlertAction
    @Binding var isPresented: Bool
    @Binding var collectionNameInputValue: String

    var collection: ScanCollection?
    var modelContext: ModelContext
    var relatedRecordID: String?
    var canExecuteAction: (() -> Bool)?
    var onActionComplete: ((ScanCollection?) -> Void)?
    var onDeleted: (() -> Void)?
    var mutationService: CollectionMutationService

    func body(content: Content) -> some View {
        content
            .alert(alertTitle, isPresented: $isPresented) {
                if action == .rename || action == .create {
                    TextField(
                        "Collection name",
                        text: $collectionNameInputValue
                    )
                }

                Button("Cancel", role: .cancel) {
                    if action == .create {
                        collectionNameInputValue = ""
                    }
                }

                Button(
                    primaryButtonTitle,
                    role: action == .delete ? .destructive : nil
                ) {
                    executeAction()
                }
            } message: {
                if let alertMessage {
                    Text(alertMessage)
                }
            }
    }

    private var alertTitle: String {
        switch action {
        case .rename:
            return "Rename collection"
        case .delete:
            return "Delete collection?"
        case .create:
            return "New collection"
        }
    }

    private var primaryButtonTitle: String {
        switch action {
        case .rename:
            return "Save"
        case .delete:
            return "Delete"
        case .create:
            return "Create"
        }
    }

    private var alertMessage: String? {
        switch action {
        case .rename:
            return nil
        case .delete:
            return "This will delete the collection folder. The scans inside will not be deleted and will remain safely in your library."
        case .create:
            return "Enter a name for this new collection."
        }
    }

    private func executeAction() {
        guard canExecuteAction?() != false else { return }

        switch action {
        case .rename:
            guard let collection,
                  mutationService.rename(
                      collection,
                      to: collectionNameInputValue,
                      in: modelContext
                  ) else { return }
            onActionComplete?(collection)

        case .delete:
            guard let collection,
                  mutationService.delete(
                      collection,
                      in: modelContext
                  ) else { return }
            onDeleted?()
            mutationService.triggerDestructiveFeedback()

        case .create:
            guard let collection = mutationService.create(
                name: collectionNameInputValue,
                relatedRecordID: relatedRecordID,
                in: modelContext
            ) else { return }
            collectionNameInputValue = ""
            onActionComplete?(collection)
        }
    }
}

@MainActor
extension View {
    func collectionRenameAlert(
        isPresented: Binding<Bool>,
        newCollectionName: Binding<String>,
        collection: ScanCollection?,
        modelContext: ModelContext,
        mutationService: CollectionMutationService? = nil
    ) -> some View {
        modifier(
            CollectionActionAlertModifier(
                action: .rename,
                isPresented: isPresented,
                collectionNameInputValue: newCollectionName,
                collection: collection,
                modelContext: modelContext,
                mutationService: mutationService ?? CollectionMutationService()
            )
        )
    }

    func collectionDeleteAlert(
        isPresented: Binding<Bool>,
        collection: ScanCollection?,
        modelContext: ModelContext,
        onDeleted: (() -> Void)? = nil,
        mutationService: CollectionMutationService? = nil
    ) -> some View {
        modifier(
            CollectionActionAlertModifier(
                action: .delete,
                isPresented: isPresented,
                collectionNameInputValue: .constant(""),
                collection: collection,
                modelContext: modelContext,
                onDeleted: onDeleted,
                mutationService: mutationService ?? CollectionMutationService()
            )
        )
    }

    func newCollectionAlert(
        isPresented: Binding<Bool>,
        newCollectionName: Binding<String>,
        modelContext: ModelContext,
        relatedRecordId: String? = nil,
        canCreate: (() -> Bool)? = nil,
        onCreated: ((ScanCollection) -> Void)? = nil,
        mutationService: CollectionMutationService? = nil
    ) -> some View {
        modifier(
            CollectionActionAlertModifier(
                action: .create,
                isPresented: isPresented,
                collectionNameInputValue: newCollectionName,
                modelContext: modelContext,
                relatedRecordID: relatedRecordId,
                canExecuteAction: canCreate,
                onActionComplete: { collection in
                    if let collection {
                        onCreated?(collection)
                    }
                },
                mutationService: mutationService ?? CollectionMutationService()
            )
        )
    }
}
