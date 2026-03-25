import SwiftUI
import SwiftData

// MARK: - Collection Alert Actions

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
    var relatedRecord: LocalScanRecord?
    
    var onActionComplete: ((ScanCollection?) -> Void)?
    var onDeleted: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert(alertTitle, isPresented: $isPresented) {
                if action == .rename || action == .create {
                    TextField("Collection name", text: $collectionNameInputValue)
                }
                
                Button("Cancel", role: .cancel) {
                    if action == .create { collectionNameInputValue = "" }
                }
                
                Button(primaryButtonTitle, role: action == .delete ? .destructive : nil) {
                    executeAction()
                }
            } message: {
                if let message = alertMessage {
                    Text(message)
                }
            }
    }
    
    private var alertTitle: String {
        switch action {
        case .rename: return "Rename collection"
        case .delete: return "Delete collection?"
        case .create: return "New collection"
        }
    }
    
    private var primaryButtonTitle: String {
        switch action {
        case .rename: return "Save"
        case .delete: return "Delete"
        case .create: return "Create"
        }
    }
    
    private var alertMessage: String? {
        switch action {
        case .rename: return nil
        case .delete: return "This will delete the collection folder. The scans inside will not be deleted and will remain safely in your library."
        case .create: return "Enter a name for this new collection."
        }
    }
    
    private func executeAction() {
        switch action {
        case .rename:
            let trimmed = collectionNameInputValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let collectionToRename = collection {
                collectionToRename.name = trimmed
                finalizeAction(triggerSuccess: true)
                onActionComplete?(collectionToRename)
            }
            
        case .delete:
            if let collectionToDelete = collection {
                onDeleted?()
                HapticManager.shared.triggerErrorThump()
                collectionToDelete.isDeleted = true
                finalizeAction(triggerSuccess: false)
            }
            
        case .create:
            let collectionName = collectionNameInputValue.isEmpty ? "Untitled" : collectionNameInputValue
            let newCollection = ScanCollection(name: collectionName)
            
            modelContext.insert(newCollection)
            
            if let record = relatedRecord {
                if record.collections == nil {
                    record.collections = []
                }
                record.collections?.append(newCollection)
            }
            
            collectionNameInputValue = ""
            finalizeAction(triggerSuccess: true)
            onActionComplete?(newCollection)
        }
    }
    
    private func finalizeAction(triggerSuccess: Bool) {
        try? modelContext.save()
        OfflineQueueManager.shared.syncCollections()
        if triggerSuccess {
            HapticManager.shared.triggerSuccessPulse()
        }
    }
}

// MARK: - ScanCollection Hashable

extension ScanCollection: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: ScanCollection, rhs: ScanCollection) -> Bool { lhs.id == rhs.id }
}

// MARK: - View Extensions

extension View {
    func collectionRenameAlert(
        isPresented: Binding<Bool>,
        newCollectionName: Binding<String>,
        collection: ScanCollection?,
        modelContext: ModelContext
    ) -> some View {
        modifier(CollectionActionAlertModifier(
            action: .rename,
            isPresented: isPresented,
            collectionNameInputValue: newCollectionName,
            collection: collection,
            modelContext: modelContext
        ))
    }
    
    func collectionDeleteAlert(
        isPresented: Binding<Bool>,
        collection: ScanCollection?,
        modelContext: ModelContext,
        onDeleted: (() -> Void)? = nil
    ) -> some View {
        modifier(CollectionActionAlertModifier(
            action: .delete,
            isPresented: isPresented,
            collectionNameInputValue: .constant(""),
            collection: collection,
            modelContext: modelContext,
            onDeleted: onDeleted
        ))
    }
    
    func newCollectionAlert(
        isPresented: Binding<Bool>,
        newCollectionName: Binding<String>,
        modelContext: ModelContext,
        relatedRecord: LocalScanRecord? = nil,
        onCreated: ((ScanCollection) -> Void)? = nil
    ) -> some View {
        modifier(CollectionActionAlertModifier(
            action: .create,
            isPresented: isPresented,
            collectionNameInputValue: newCollectionName,
            modelContext: modelContext,
            relatedRecord: relatedRecord,
            onActionComplete: { newCol in
                if let newCol = newCol {
                    onCreated?(newCol)
                }
            }
        ))
    }
}
