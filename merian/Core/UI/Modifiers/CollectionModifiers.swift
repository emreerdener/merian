import SwiftUI
import SwiftData

// MARK: - Collection Management Alerts

struct CollectionRenameAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var newCollectionName: String
    var collection: ScanCollection?
    var modelContext: ModelContext
    
    func body(content: Content) -> some View {
        content
            .alert("Rename collection", isPresented: $isPresented) {
                TextField("Collection name", text: $newCollectionName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let collectionToRename = collection {
                        collectionToRename.name = trimmed
                        try? modelContext.save()
                        HapticManager.shared.triggerSuccessPulse()
                    }
                }
            }
    }
}

struct CollectionDeleteAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    var collection: ScanCollection?
    var modelContext: ModelContext
    var onDeleted: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert("Delete collection?", isPresented: $isPresented) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let collectionToDelete = collection {
                        onDeleted?()
                        HapticManager.shared.triggerErrorThump()
                        modelContext.delete(collectionToDelete)
                        try? modelContext.save()
                    }
                }
            } message: {
                Text("This will delete the collection folder. The scans inside will not be deleted and will remain safely in your library.")
            }
    }
}

// MARK: - New Collection Alerts

struct NewCollectionAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var newCollectionName: String
    var modelContext: ModelContext
    var relatedRecord: LocalScanRecord?
    var onCreated: ((ScanCollection) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert("New collection", isPresented: $isPresented) {
                TextField("Collection name", text: $newCollectionName)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
                Button("Create") {
                    let collectionName = newCollectionName.isEmpty ? "Untitled" : newCollectionName
                    let collection = ScanCollection(name: collectionName)
                    
                    modelContext.insert(collection)
                    
                    if let record = relatedRecord {
                        if record.collections == nil {
                            record.collections = []
                        }
                        record.collections?.append(collection)
                    }
                    
                    try? modelContext.save()
                    newCollectionName = ""
                    
                    HapticManager.shared.triggerSuccessPulse()
                    onCreated?(collection)
                }
            } message: {
                Text("Enter a name for this new collection.")
            }
    }
}

// MARK: - View Extensions

extension View {
    func collectionRenameAlert(
        isPresented: Binding<Bool>,
        newCollectionName: Binding<String>,
        collection: ScanCollection?,
        modelContext: ModelContext
    ) -> some View {
        modifier(CollectionRenameAlertModifier(
            isPresented: isPresented,
            newCollectionName: newCollectionName,
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
        modifier(CollectionDeleteAlertModifier(
            isPresented: isPresented,
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
        modifier(NewCollectionAlertModifier(
            isPresented: isPresented,
            newCollectionName: newCollectionName,
            modelContext: modelContext,
            relatedRecord: relatedRecord,
            onCreated: onCreated
        ))
    }
}
