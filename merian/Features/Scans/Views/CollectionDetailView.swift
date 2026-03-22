import SwiftUI
import SwiftData

struct CollectionDetailView: View {
    // MARK: - State Dependencies
    @Bindable var collection: ScanCollection
    @Binding var isInsightSheetOpen: Bool
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    // MARK: - Interface State
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var showScanSelection = false
    @State private var showDeleteConfirmation = false
    
    // MARK: - View Layout
    var body: some View {
        ScrollView {
            if let scans = collection.scans, !scans.isEmpty {
                // To ensure visually consistent ordering, sort by timestamp
                let sortedScans = scans.sorted(by: { $0.timestamp > $1.timestamp })
                
                ScansGrid(scans: sortedScans, onSelect: { scan in
                    selectedScanForInsight = scan
                    inferenceEngine.load(from: scan)
                }, onDelete: { scan in
                    scanToDelete = scan
                    showDeleteConfirmation = true
                }) { scan in
                    Button(role: .destructive) {
                        removeFromCollection(scan: scan)
                    } label: {
                        Label("Remove from collection", systemImage: "minus.circle")
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

        // MARK: - View Modifiers
        .navigationTitle(collection.name)
        .toolbar { trailingToolbar }
        .sheet(item: $selectedScanForInsight) { scan in
            InsightSheetView(isPresented: Binding(
                get: { selectedScanForInsight != nil },
                set: { if !$0 { selectedScanForInsight = nil } }
            ))
        }
        .sheet(isPresented: $showScanSelection) {
            SelectMultipleScansView(collection: collection)
        }
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            record: scanToDelete,
            modelContext: modelContext
        ) {
            scanToDelete = nil
        }
    }
    
    // MARK: - Layout Subcomponents
    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: {
                showScanSelection = true
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .buttonBorderShape(.circle)
        }
    }
    
    // MARK: - Action Handlers
    private func removeFromCollection(scan: LocalScanRecord) {
        scan.collections?.removeAll(where: { $0.id == collection.id })
        try? modelContext.save()
    }
}
