import SwiftUI
import SwiftData

struct ScanSelectionSheetView: View {
    @Bindable var collection: ScanCollection
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    
// Columns extracted natively
    
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
                            iconName: "photo.on.rectangle.angled",
                            title: "No Scans in Library",
                            message: "Start exploring and capture your first scan to build your collections natively."
                        )
                        .foregroundColor(.white) // Safely inherits dark mode bounds cleanly
                    } else {
                        ScanGridMatrix(
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
    
    private func toggleSelection(scan: LocalScanRecord) {
        if let existingScans = collection.scans, existingScans.contains(where: { $0.id == scan.id }) {
            scan.collections?.removeAll(where: { $0.id == collection.id })
        } else {
            if scan.collections == nil {
                scan.collections = []
            }
            scan.collections?.append(collection)
        }
        try? modelContext.save()
    }
}
