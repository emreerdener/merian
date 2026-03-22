import SwiftUI
import SwiftData

struct CollectionsView: View {
    let collections: [ScanCollection]
    @Binding var isInsightSheetOpen: Bool
    
    @Environment(\.modelContext) private var modelContext
    @State private var nonBioCount: Int = 0
    @State private var collectionToEdit: ScanCollection?
    @State private var showRenameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var newCollectionName = ""
    
    var body: some View {
        ScrollView {
            let userCollections = collections.filter { $0.name != "Favorites" }
            
            // MARK: - Promoted Links (Favorites & Non-biological)
            if let favorites = collections.first(where: { $0.name == "Favorites" }) {
                NavigationLink {
                    CollectionDetailView(collection: favorites, isInsightSheetOpen: $isInsightSheetOpen)
                } label: {
                    HStack {
                        Image(systemName: "heart")
                            .foregroundColor(.secondary)    
                        Text("Favorites")   
                            .font(.headline)
                        Spacer()
                        Text("\(favorites.scans?.count ?? 0)")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
            
            NavigationLink {
                NonBiologicalScansView(isInsightSheetOpen: $isInsightSheetOpen)
            } label: {
                HStack {
                    Image(systemName: "cube")
                        .foregroundColor(.secondary)
                    Text("Non-biological")
                        .font(.headline)
                    Spacer()
                    Text("\(nonBioCount)")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.bottom, 16)
            
            // MARK: - User Custom Collections Grid
            if userCollections.isEmpty {
                EmptyStateView(
                    iconName: "folder",
                    title: "No collections",
                    message: "Create your first collection to start organizing your scans."
                )
                .padding(.top, 32)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(userCollections) { collection in
                        NavigationLink {
                            CollectionDetailView(collection: collection, isInsightSheetOpen: $isInsightSheetOpen)
                        } label: {
                            ZStack {
                                if let firstScan = collection.scans?.first {
                                    GeometryReader { geo in
                                        ScanThumbnail(imagePath: firstScan.localImagePath, fallbackImageUrl: firstScan.referenceImageUrl)
                                            .frame(width: geo.size.width, height: geo.size.width)
                                            .clipped()
                                    }
                                    .aspectRatio(1.0, contentMode: .fill)
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .aspectRatio(1.0, contentMode: .fill)
                                        .overlay(
                                            Image(systemName: "photo.on.rectangle")
                                                .font(.system(size: 24))
                                                .foregroundColor(.secondary)
                                                // Natively shifts the icon mathematically up exactly half the height
                                                // of the bottom text panel, centering it perfectly within the visible area.
                                                .offset(y: -24)
                                        )
                                }
                                
                                VStack {
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(collection.name)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("\(collection.scans?.count ?? 0) Scans")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                                }
                            }
                            .cornerRadius(12)
                            .clipped()
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                collectionToEdit = collection
                                newCollectionName = collection.name
                                showRenameAlert = true
                            } label: {
                                Label("Rename collection", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                collectionToEdit = collection
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete collection", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .alert("Rename collection", isPresented: $showRenameAlert) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let collection = collectionToEdit {
                    collection.name = trimmed
                    try? modelContext.save()
                    HapticManager.shared.triggerSuccessPulse()
                }
            }
        }
        .alert("Delete collection?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let collection = collectionToEdit {
                    HapticManager.shared.triggerErrorThump()
                    modelContext.delete(collection)
                    try? modelContext.save()
                }
            }
        } message: {
            Text("This will delete the collection folder. The scans inside will not be deleted and will remain safely in your library.")
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.collections)
        .task {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.isBiological == false || $0.commonName == "Unknown Subject" })
            if let count = try? modelContext.fetchCount(descriptor) {
                nonBioCount = count
            }
        }
    }
}
