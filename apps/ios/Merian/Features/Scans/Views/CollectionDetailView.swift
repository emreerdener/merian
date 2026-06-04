import SwiftData
import SwiftUI

struct CollectionDetailView: View {
    // MARK: - State Dependencies
    @Bindable var collection: ScanCollection

    // Fetch V13-typed scans and filter by this collection.
    // We can't traverse collection.scans directly because ScanCollection is typealiased
    // from V12 and its relationship is statically typed as [V12.LocalScanRecord].
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allScans: [LocalScanRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) var inferenceEngine
    
    // MARK: - Interface State
    @State private var memberScans: [LocalScanRecord] = []
    @State private var scanToDelete: String?
    @State private var selectedScanForInsight: ScanInsightRoute?
    @State private var showScanSelection = false
    @State private var showDeleteConfirmation = false
    @State private var newCollectionName: String = ""
    @State private var showRenameAlert = false
    @State private var showCollectionDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View Layout
    var body: some View {
        ScrollView {
            if !memberScans.isEmpty {
                
                ScansGrid(scans: memberScans, onSelect: { scan in
                    inferenceEngine.load(from: scan)
                    selectedScanForInsight = ScanInsightRoute(scanId: scan.id)
                }, onDelete: { scan in
                    scanToDelete = scan.id
                    showDeleteConfirmation = true
                }, onAddScans: {
                    showScanSelection = true
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
        .navigationDestination(item: $selectedScanForInsight) { route in
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedScanForInsight != nil },
                    set: { if !$0 { selectedScanForInsight = nil } }
                ),
                initialScanId: route.scanId,
                inferenceEngine: inferenceEngine,
                presentationStyle: .embeddedInScansLibrary
            )
        }
        .sheet(isPresented: $showScanSelection) {
            SelectMultipleScansView(collection: collection)
        }
        .task {
            refreshMemberScans()
        }
        .task(id: allScans.count) {
            refreshMemberScans()
        }
        .onReceive(ScanLibraryEvents.libraryDidUpdatePublisher()) { _ in
            refreshMemberScans()
        }
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            scanId: scanToDelete,
            modelContext: modelContext
        ) {
            scanToDelete = nil
        }
        .collectionRenameAlert(
            isPresented: $showRenameAlert,
            newCollectionName: $newCollectionName,
            collection: collection,
            modelContext: modelContext
        )
        .collectionDeleteAlert(
            isPresented: $showCollectionDeleteConfirmation,
            collection: collection,
            modelContext: modelContext,
            onDeleted: { dismiss() }
        )
    }
    
    // MARK: - Layout Subcomponents
    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if collection.name == "Favorites" {
                Button(action: {
                    showScanSelection = true
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
            } else {
                Menu {
                    Button {
                        showScanSelection = true
                    } label: {
                        Label("Add scans", systemImage: "plus")
                    }
                    
                    Divider()
                    
                    Button {
                        newCollectionName = collection.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename collection", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        showCollectionDeleteConfirmation = true
                    } label: {
                        Label("Delete collection", systemImage: "trash")
                        .foregroundColor(.red)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
    
    // MARK: - Action Handlers
    private func removeFromCollection(scan: LocalScanRecord) {
        var updatedCollections = scan.collections ?? []
        let originalCount = updatedCollections.count
        updatedCollections.removeAll(where: { $0.id == collection.id })
        guard updatedCollections.count != originalCount else { return }

        scan.collections = updatedCollections

        do {
            try modelContext.save()
            ScanLibraryEvents.postLibraryDidUpdate()
            refreshMemberScans()
            OfflineQueueManager.shared.enqueueCollectionSync()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("CollectionDetailView: failed removing scan from collection: \(error, privacy: .private)")
        }
    }

    private func refreshMemberScans() {
        let snapshot = CollectionMembershipSnapshot(scans: allScans)
        memberScans = snapshot.memberScans(for: collection.id, from: allScans)
    }
}
