import SwiftUI

struct AddCollectionButton: View {
    let collections: [ScanCollection]
    let selectedCollectionIds: Set<String>
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let hasScanId: Bool
    
    var body: some View {
        Menu {
            if let favorites = collections.first(where: { $0.name == "Favorites" && !$0.isDeleted }) {
                let isFavorited = selectedCollectionIds.contains(favorites.id)
                Button(action: { toggleScanInCollection(favorites) }) {
                    Label("Favorites", systemImage: isFavorited ? "heart.fill" : "heart")
                }
                Divider()
            }
            
            ForEach(collections.filter { $0.name != "Favorites" && !$0.isDeleted }) { collection in
                let isSelected = selectedCollectionIds.contains(collection.id)
                Button(action: { toggleScanInCollection(collection) }) {
                    Label(collection.name, systemImage: isSelected ? "checkmark.circle.fill" : "folder")
                }
            }
            Divider()
            Button(action: { showNewCollectionAlert = true }) {
                Label("New Collection...", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                Text("Add to collection")
            }
            .padding(.horizontal, 8)
        }
        .disabled(!hasScanId)
    }
}
