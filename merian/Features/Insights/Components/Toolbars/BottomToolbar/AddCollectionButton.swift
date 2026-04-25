import SwiftUI

struct AddCollectionButton: View {
    let collections: [ScanCollection]
    let activeLocalRecord: LocalScanRecord?
    let toggleScanInCollection: (ScanCollection) -> Void
    @Binding var showNewCollectionAlert: Bool
    let hasScanId: Bool
    
    var body: some View {
        Menu {
            if let favorites = collections.first(where: { $0.name == "Favorites" }) {
                let isFavorited = activeLocalRecord?.collections?.contains(where: { $0.id == favorites.id }) ?? false
                Button(action: { toggleScanInCollection(favorites) }) {
                    Label("Favorites", systemImage: isFavorited ? "heart.fill" : "heart")
                }
                Divider()
            }
            
            ForEach(collections.filter { $0.name != "Favorites" }) { collection in
                let isSelected = activeLocalRecord?.collections?.contains(where: { $0.id == collection.id }) ?? false
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
