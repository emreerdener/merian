import SwiftUI
import SwiftData

struct SelectMultipleScansView: View {
    // MARK: - State Dependencies
    @Bindable var collection: ScanCollection
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    // MARK: - View Layout
    var body: some View {
        NavigationStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .ignoresSafeArea()
                
                ScrollView {
                    if allRecords.isEmpty {
                        EmptyStateView(
                            iconName: "viewfinder",
                            title: "No scans in library",
                            message: "Start exploring and capture your first scan to build your collections natively."
                        )
                        .foregroundColor(.white) // Safely inherits dark mode bounds cleanly
                    } else {
                        ScansGrid(
                            scans: allRecords,
                            onSelect: { scan in
                                toggleSelection(scan: scan)
                            },
                            isSelected: { scan in
                                collection.scans?.contains(where: { $0.id == scan.id }) ?? false
                            }
                        )
                    }
                }
            }
            
            // MARK: - View Modifiers
            .navigationTitle("Add to \(collection.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Action Handlers
    private func toggleSelection(scan: LocalScanRecord) {
        if let existingScans = collection.scans, existingScans.contains(where: { $0.id == scan.id }) {
            var updatedCollections = scan.collections ?? []
            updatedCollections.removeAll(where: { $0.id == collection.id })
            scan.collections = updatedCollections
        } else {
            var updatedCollections = scan.collections ?? []
            if !updatedCollections.contains(where: { $0.id == collection.id }) {
                updatedCollections.append(collection)
                scan.collections = updatedCollections
            }
        }
        try? modelContext.save()
        OfflineQueueManager.shared.enqueueCollectionSync()
    }
}
