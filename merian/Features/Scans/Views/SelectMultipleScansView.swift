import SwiftData
import SwiftUI

struct SelectMultipleScansView: View {
    // MARK: - State Dependencies
    @Bindable var collection: ScanCollection
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @State private var collectionSnapshot = CollectionMembershipSnapshot.empty
    
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
                                collectionSnapshot.contains(scanID: scan.id, in: collection.id)
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
        .task {
            refreshCollectionSnapshot()
        }
        .task(id: allRecords.count) {
            refreshCollectionSnapshot()
        }
        .onReceive(ScanLibraryEvents.libraryDidUpdatePublisher()) { _ in
            refreshCollectionSnapshot()
        }
    }
    
    // MARK: - Action Handlers
    private func toggleSelection(scan: LocalScanRecord) {
        if collectionSnapshot.contains(scanID: scan.id, in: collection.id) {
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

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("SelectMultipleScansView: failed to update collection membership: \(error, privacy: .private)")
            HapticManager.shared.triggerErrorThump()
            return
        }

        ScanLibraryEvents.postLibraryDidUpdate()
        refreshCollectionSnapshot()
        OfflineQueueManager.shared.enqueueCollectionSync()
    }

    private func refreshCollectionSnapshot() {
        collectionSnapshot = CollectionMembershipSnapshot(scans: allRecords)
    }
}
