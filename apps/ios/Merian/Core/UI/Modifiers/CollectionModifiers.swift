import SwiftData
import SwiftUI

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
    var relatedRecordId: String?
    
    var canExecuteAction: (() -> Bool)?
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
        guard canExecuteAction?() != false else { return }

        switch action {
        case .rename:
            guard let collectionToRename = collection else { return }
            guard let validatedName = resolveValidatedCollectionName(
                allowUntitledFallback: false,
                excludingCollectionID: collectionToRename.id
            ) else { return }
            guard collectionToRename.name != validatedName else { return }

            collectionToRename.name = validatedName
            if finalizeAction(triggerSuccess: true) {
                onActionComplete?(collectionToRename)
            }
            
        case .delete:
            if let collectionToDelete = collection {
                collectionToDelete.isDeleted = true
                if finalizeAction(triggerSuccess: false) {
                    onDeleted?()
                    HapticManager.shared.triggerErrorThump()
                }
            }
            
        case .create:
            guard let validatedName = resolveValidatedCollectionName(
                allowUntitledFallback: true,
                excludingCollectionID: nil
            ) else { return }
            let newCollection = ScanCollection(name: validatedName)
            
            modelContext.insert(newCollection)
            
            if let record = resolveRelatedRecord() {
                var updatedCollections = record.collections ?? []
                updatedCollections.append(newCollection)
                record.collections = updatedCollections
            }
            
            if finalizeAction(triggerSuccess: true) {
                collectionNameInputValue = ""
                onActionComplete?(newCollection)
            }
        }
    }
    
    @discardableResult
    private func finalizeAction(triggerSuccess: Bool) -> Bool {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("CollectionActionAlertModifier: failed to save context: \(error, privacy: .private)")
            return false
        }
        OfflineQueueManager.shared.enqueueCollectionSync()
        if triggerSuccess {
            HapticManager.shared.triggerSuccessPulse()
        }
        return true
    }

    private func resolveValidatedCollectionName(
        allowUntitledFallback: Bool,
        excludingCollectionID: String?
    ) -> String? {
        let trimmed = collectionNameInputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty && allowUntitledFallback ? "Untitled" : trimmed

        guard !resolvedName.isEmpty else {
            HapticManager.shared.triggerErrorThump()
            return nil
        }

        if resolvedName.compare("Favorites", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            HapticManager.shared.triggerErrorThump()
            MerianLog.data.debug("CollectionActionAlertModifier: blocked reserved collection name Favorites")
            return nil
        }

        var descriptor = FetchDescriptor<ScanCollection>(predicate: #Predicate { !$0.isDeleted })
        descriptor.fetchLimit = 500
        let existingCollections = (try? modelContext.fetch(descriptor)) ?? []

        let hasDuplicate = existingCollections.contains { existing in
            guard existing.id != excludingCollectionID else { return false }
            return existing.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(resolvedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        if hasDuplicate {
            HapticManager.shared.triggerErrorThump()
            MerianLog.data.debug("CollectionActionAlertModifier: blocked duplicate collection name \(resolvedName, privacy: .private)")
            return nil
        }

        return resolvedName
    }

    private func resolveRelatedRecord() -> LocalScanRecord? {
        guard let relatedRecordId else { return nil }
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == relatedRecordId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
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
        relatedRecordId: String? = nil,
        canCreate: (() -> Bool)? = nil,
        onCreated: ((ScanCollection) -> Void)? = nil
    ) -> some View {
        modifier(CollectionActionAlertModifier(
            action: .create,
            isPresented: isPresented,
            collectionNameInputValue: newCollectionName,
            modelContext: modelContext,
            relatedRecordId: relatedRecordId,
            canExecuteAction: canCreate,
            onActionComplete: { newCol in
                if let newCol = newCol {
                    onCreated?(newCol)
                }
            }
        ))
    }
}
