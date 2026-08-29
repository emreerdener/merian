import SwiftData
import SwiftUI

struct CollectionDetailView: View {
    @Bindable var collection: ScanCollection
    let scans: [LocalScanRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: CollectionDetailViewModel
    @State private var scanToDelete: String?
    @State private var selectedScanForInsight: ScanInsightRoute?
    @State private var showScanSelection = false
    @State private var showDeleteConfirmation = false
    @State private var newCollectionName = ""
    @State private var showRenameAlert = false
    @State private var showCollectionDeleteConfirmation = false

    private let dependencies: CollectionsDependencies?

    init(
        collection: ScanCollection,
        scans: [LocalScanRecord] = [],
        dependencies: CollectionsDependencies? = nil
    ) {
        self.collection = collection
        self.scans = scans
        self.dependencies = dependencies
        _viewModel = State(
            initialValue: CollectionDetailViewModel(
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if viewModel.memberScans.isEmpty {
                    emptyState(minimumHeight: geometry.size.height)
                } else {
                    scansGrid
                }
            }
        }
        .navigationTitle(collection.name)
        .toolbar { trailingToolbar }
        .navigationDestination(item: $selectedScanForInsight) { route in
            insightDestination(for: route)
        }
        .sheet(isPresented: $showScanSelection) {
            SelectMultipleScansView(
                collection: collection,
                scans: scans,
                dependencies: dependencies
            )
        }
        .task(id: membershipRefreshIdentity) {
            refresh()
        }
        .onReceive(viewModel.events) { event in
            guard case .scanLibraryChanged = event else { return }
            refresh()
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
            modelContext: modelContext,
            mutationService: viewModel.mutationService
        )
        .collectionDeleteAlert(
            isPresented: $showCollectionDeleteConfirmation,
            collection: collection,
            modelContext: modelContext,
            onDeleted: { dismiss() },
            mutationService: viewModel.mutationService
        )
    }

    private var scansGrid: some View {
        ScansGrid(
            scans: viewModel.memberScans,
            onSelect: { scan in
                selectedScanForInsight = ScanInsightRoute(scanId: scan.id)
            },
            onDelete: { scan in
                scanToDelete = scan.id
                showDeleteConfirmation = true
            },
            onAddScans: {
                showScanSelection = true
            }
        ) { scan in
            Button(role: .destructive) {
                viewModel.remove(
                    scan,
                    from: collection,
                    scans: scans,
                    in: modelContext
                )
            } label: {
                Label(
                    "Remove from collection",
                    systemImage: "minus.circle"
                )
            }
        }
    }

    private func emptyState(minimumHeight: CGFloat) -> some View {
        EmptyStateView(
            iconName: "photo.on.rectangle.angled",
            title: "Empty collection",
            message: "Add scans from your library to start building your collection."
        ) {
            Button {
                showScanSelection = true
            } label: {
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
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
    }

    private func insightDestination(
        for route: ScanInsightRoute
    ) -> some View {
        LocalScanInsightLoader(scanId: route.scanId) {
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedScanForInsight != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectedScanForInsight = nil
                        }
                    }
                ),
                initialScanId: route.scanId,
                inferenceEngine: inferenceEngine,
                presentationStyle: .embeddedInScansLibrary
            )
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if collection.name == "Favorites" {
                Button {
                    showScanSelection = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
            } else {
                collectionMenu
            }
        }
    }

    private var collectionMenu: some View {
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

    private func refresh() {
        viewModel.refresh(scans: scans, collectionID: collection.id)
    }

    private var membershipRefreshIdentity: [String] {
        viewModel.refreshIdentity(
            scans: scans,
            collectionID: collection.id
        )
    }
}
