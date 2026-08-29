import SwiftUI

struct AddCollectionTopMenu: View {
    let collections: [ScanCollection]
    let selectedCollectionIds: Set<String>
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let hasScanId: Bool

    var body: some View {
        Menu {
            AddCollectionMenuItems(
                collections: collections,
                selectedCollectionIds: selectedCollectionIds,
                toggleScanInCollection: toggleScanInCollection,
                showNewCollectionAlert: $showNewCollectionAlert
            )
        } label: {
            Label("Add to collection", systemImage: "folder.badge.plus")
        }
        .disabled(!hasScanId)
    }
}

private struct AddCollectionMenuItems: View {
    let collections: [ScanCollection]
    let selectedCollectionIds: Set<String>
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool

    var body: some View {
        if let favorites = collections.first(where: { $0.name == "Favorites" && !$0.isPendingDeletion }) {
            let isFavorited = selectedCollectionIds.contains(favorites.id)
            Button(action: { toggleScanInCollection(favorites) }) {
                Label("Favorites", systemImage: isFavorited ? "heart.fill" : "heart")
            }
            Divider()
        }

        ForEach(collections.filter { $0.name != "Favorites" && !$0.isPendingDeletion }) { collection in
            let isSelected = selectedCollectionIds.contains(collection.id)
            Button(action: { toggleScanInCollection(collection) }) {
                Label(collection.name, systemImage: isSelected ? "checkmark.circle.fill" : "folder")
            }
        }
        Divider()
        Button(action: { showNewCollectionAlert = true }) {
            Label("New Collection...", systemImage: "folder.badge.plus")
        }
    }
}
