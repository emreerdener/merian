import SwiftData
import SwiftUI

struct SmartCollectionDetailView: View {
    let snapshot: SmartCollectionSnapshot
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void

    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allScans: [LocalScanRecord]
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.dismiss) private var dismiss

    @State private var selectedScanForInsight: ScanInsightRoute?

    private var liveSnapshot: SmartCollectionSnapshot {
        SmartCollectionSuggester.refreshedSnapshot(for: snapshot, from: allScans)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if liveSnapshot.scans.isEmpty {
                    EmptyStateView(
                        iconName: liveSnapshot.iconName,
                        title: liveSnapshot.title,
                        message: "This smart collection no longer has matching scans."
                    )
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                } else {
                    ScansGrid(
                        scans: liveSnapshot.scans,
                        onSelect: { scan in
                            inferenceEngine.load(from: scan)
                            selectedScanForInsight = ScanInsightRoute(scanId: scan.id)
                        }
                    )
                }
            }
        }
        .navigationTitle(snapshot.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if snapshot.isHideable {
                    Menu {
                        Button(role: .destructive) {
                            hideSmartCollection()
                        } label: {
                            Label("Hide smart collection", systemImage: "eye.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
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
    }

    private func hideSmartCollection() {
        guard snapshot.isHideable else { return }
        onHideSmartCollection(snapshot)
        HapticManager.shared.triggerLightImpact()
        dismiss()
    }
}
