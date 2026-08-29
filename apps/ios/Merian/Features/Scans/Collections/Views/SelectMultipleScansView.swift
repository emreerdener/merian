import SwiftData
import SwiftUI

struct SelectMultipleScansView: View {
    @Bindable var collection: ScanCollection
    let scans: [LocalScanRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SelectMultipleScansViewModel

    init(
        collection: ScanCollection,
        scans: [LocalScanRecord] = [],
        dependencies: CollectionsDependencies? = nil
    ) {
        self.collection = collection
        self.scans = scans
        _viewModel = State(
            initialValue: SelectMultipleScansViewModel(
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .ignoresSafeArea()

                ScrollView {
                    if scans.isEmpty {
                        EmptyStateView(
                            iconName: "viewfinder",
                            title: "No scans in library",
                            message: "Start exploring and capture your first scan to build your collections natively."
                        )
                        .foregroundColor(.white)
                    } else {
                        ScansGrid(
                            scans: scans,
                            onSelect: toggleSelection,
                            isSelected: { scan in
                                viewModel.contains(
                                    scanID: scan.id,
                                    collectionID: collection.id
                                )
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
        .task(id: membershipRefreshIdentity) {
            refresh()
        }
        .onReceive(viewModel.events) { event in
            guard case .scanLibraryChanged = event else { return }
            refresh()
        }
    }

    private func toggleSelection(_ scan: LocalScanRecord) {
        viewModel.toggle(
            scan,
            in: collection,
            scans: scans,
            modelContext: modelContext
        )
    }

    private func refresh() {
        viewModel.refresh(scans: scans)
    }

    private var membershipRefreshIdentity: [String] {
        viewModel.refreshIdentity(
            scans: scans,
            collectionID: collection.id
        )
    }
}
