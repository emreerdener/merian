import SwiftUI
import SwiftData

struct CollectionDetailView: View {
    @Bindable var collection: ScanCollection
    @Binding var isInsightSheetOpen: Bool
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var showScanSelection = false
    @State private var showDeleteConfirmation = false
    
// Generic grid handles struct spacing
    
    var body: some View {
        ScrollView {
            if let scans = collection.scans, !scans.isEmpty {
                // To ensure visually consistent ordering, sort by timestamp
                let sortedScans = scans.sorted(by: { $0.timestamp > $1.timestamp })
                
                ScanGridMatrix(scans: sortedScans, onSelect: { scan in
                    selectedScanForInsight = scan
                    inferenceEngine.load(from: scan)
                }) { scan, thumbnail in
                    thumbnail
                        .contextMenu {
                            Button(role: .destructive) {
                                removeFromCollection(scan: scan)
                            } label: {
                                Label("Remove from collection", systemImage: "minus.circle")
                            }
                            
                            Button(role: .destructive) {
                                scanToDelete = scan
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete scan permanently", systemImage: "trash")
                            }
                        }
                }
            } else {
                EmptyStateView(
                    iconName: "photo.on.rectangle.angled",
                    title: "Empty collection",
                    message: "Add scans from your library to start building your collection."
                ) {
                    Button(action: { showScanSelection = true }) {
                        Text("Explore library")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showScanSelection = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
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
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            record: scanToDelete,
            modelContext: modelContext
        ) {
            scanToDelete = nil
        }
    }
    
    private func removeFromCollection(scan: LocalScanRecord) {
        if let index = collection.scans?.firstIndex(where: { $0.id == scan.id }) {
            collection.scans?.remove(at: index)
            try? modelContext.save()
        }
    }
}
