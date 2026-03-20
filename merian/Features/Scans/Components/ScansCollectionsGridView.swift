import SwiftUI
import SwiftData

struct ScansCollectionsGridView: View {
    let collections: [ScanCollection]
    @Binding var isInsightSheetOpen: Bool
    
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == false || $0.commonName == "Unknown Subject" }) 
    private var nonBioRecords: [LocalScanRecord]
    
    var body: some View {
        ScrollView {
            let userCollections = collections.filter { $0.name != "Favorites" }
            if userCollections.isEmpty {
                EmptyStateView(
                    iconName: "folder",
                    title: "No collections",
                    message: "Create your first collection to start organizing your scans."
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(userCollections) { collection in
                        NavigationLink {
                            CollectionDetailView(collection: collection, isInsightSheetOpen: $isInsightSheetOpen)
                        } label: {
                            ZStack {
                                if let firstScan = collection.scans?.first {
                                    GeometryReader { geo in
                                        ScansThumbnailView(imagePath: firstScan.localImagePath, fallbackImageUrl: firstScan.referenceImageUrl)
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
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            
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
                    Text("\(nonBioRecords.count)")
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
            .padding(.vertical, 8)
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.collections)
    }
}
