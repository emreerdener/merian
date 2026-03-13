import SwiftUI
import SwiftData

struct CollectionDetailView: View {
    @Bindable var collection: ScanCollection
    @Binding var isInsightSheetOpen: Bool
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var showScanSelection = false
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            if let scans = collection.scans, !scans.isEmpty {
                // To ensure visually consistent ordering, sort by timestamp
                let sortedScans = scans.sorted(by: { $0.timestamp > $1.timestamp })
                
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(sortedScans) { scan in
                        Button(action: {
                            selectedScanForInsight = scan
                            inferenceEngine.load(from: scan)
                        }) {
                            Group {
                                if let imagePath = scan.localImagePath {
                                    LifeListThumbnailView(imagePath: imagePath, fallbackImageUrl: scan.referenceImageUrl)
                                } else {
                                    Color.clear
                                        .aspectRatio(1.0, contentMode: .fit)
                                        .overlay(
                                            Rectangle().fill(Color.gray.opacity(0.3))
                                        )
                                        .clipped()
                                }
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                removeFromCollection(scan: scan)
                            } label: {
                                Label("Remove from Collection", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Spacer().frame(height: 80)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary)
                    Text("Empty Collection")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Add scans from your library to start building your collection.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button(action: { showScanSelection = true }) {
                        Text("Explore Library")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showScanSelection = true
                }) {
                    Text("Add Scans")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .sheet(item: $selectedScanForInsight) { scan in
            InsightSheetView(isPresented: Binding(
                get: { selectedScanForInsight != nil },
                set: { if !$0 { selectedScanForInsight = nil } }
            ))
        }
        .sheet(isPresented: $showScanSelection) {
            ScanSelectionSheetView(collection: collection)
        }
    }
    
    private func removeFromCollection(scan: LocalScanRecord) {
        if let index = collection.scans?.firstIndex(where: { $0.id == scan.id }) {
            collection.scans?.remove(at: index)
            try? modelContext.save()
        }
    }
}
