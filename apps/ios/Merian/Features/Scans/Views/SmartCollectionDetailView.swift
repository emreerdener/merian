import SwiftData
import SwiftUI

struct SmartCollectionDetailView: View {
    let snapshot: SmartCollectionSnapshot
    let collections: [ScanCollection]

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.dismiss) private var dismiss

    @State private var selectedScanForInsight: ScanInsightRoute?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            if snapshot.scans.isEmpty {
                EmptyStateView(
                    iconName: snapshot.iconName,
                    title: snapshot.title,
                    message: "This smart collection no longer has matching scans."
                )
            } else {
                ScansGrid(
                    scans: snapshot.scans,
                    onSelect: { scan in
                        inferenceEngine.load(from: scan)
                        selectedScanForInsight = ScanInsightRoute(scanId: scan.id)
                    }
                )
            }
        }
        .navigationTitle(snapshot.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveSmartCollection()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isSaving || snapshot.scans.isEmpty)
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
        .alert("Could not save collection", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
    }

    private func saveSmartCollection() {
        guard !isSaving else { return }
        isSaving = true

        do {
            _ = try SmartCollectionSaver.save(
                snapshot: snapshot,
                existingCollections: collections,
                modelContext: modelContext
            )
            HapticManager.shared.triggerSuccessPulse()
            dismiss()
        } catch {
            saveErrorMessage = "Please try again."
            HapticManager.shared.triggerErrorThump()
        }

        isSaving = false
    }
}
