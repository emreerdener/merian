import SwiftUI

struct SmartCollectionDetailView: View {
    let snapshot: SmartCollectionSnapshot
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void
    let scans: [LocalScanRecord]

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: SmartCollectionDetailViewModel
    @State private var selectedScanForInsight: ScanInsightRoute?

    init(
        snapshot: SmartCollectionSnapshot,
        onHideSmartCollection: @escaping (SmartCollectionSnapshot) -> Void,
        scans: [LocalScanRecord]? = nil,
        dependencies: CollectionsDependencies? = nil
    ) {
        self.snapshot = snapshot
        self.onHideSmartCollection = onHideSmartCollection
        self.scans = scans ?? snapshot.scans
        _viewModel = State(
            initialValue: SmartCollectionDetailViewModel(
                snapshot: snapshot,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if viewModel.liveSnapshot.scans.isEmpty {
                    emptyState(minimumHeight: geometry.size.height)
                } else {
                    ScansGrid(
                        scans: viewModel.liveSnapshot.scans,
                        onSelect: { scan in
                            selectedScanForInsight = ScanInsightRoute(
                                scanId: scan.id
                            )
                        }
                    )
                }
            }
        }
        .navigationTitle(snapshot.title)
        .toolbar { trailingToolbar }
        .navigationDestination(item: $selectedScanForInsight) { route in
            insightDestination(for: route)
        }
        .task(id: refreshIdentity) {
            refresh()
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case .scanLibraryChanged,
                 .exploreShareStateChanged:
                refresh()
            default:
                break
            }
        }
    }

    private func emptyState(minimumHeight: CGFloat) -> some View {
        EmptyStateView(
            iconName: viewModel.liveSnapshot.iconName,
            title: viewModel.liveSnapshot.title,
            message: "This smart collection no longer has matching scans."
        )
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if snapshot.isHideable {
                Menu {
                    Button(role: .destructive) {
                        hideSmartCollection()
                    } label: {
                        Label(
                            "Hide smart collection",
                            systemImage: "eye.slash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
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

    private func refresh() {
        viewModel.refresh(snapshot: snapshot, scans: scans)
    }

    private var refreshIdentity: CollectionScanRefreshIdentity {
        viewModel.refreshIdentity(scans: scans)
    }

    private func hideSmartCollection() {
        if viewModel.hide(
            snapshot: snapshot,
            onHide: onHideSmartCollection
        ) {
            dismiss()
        }
    }
}
