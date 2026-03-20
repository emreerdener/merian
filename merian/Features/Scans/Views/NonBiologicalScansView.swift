import SwiftUI
import SwiftData

struct NonBiologicalScansView: View {
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == false || $0.commonName == "Unknown Subject" }, sort: \.timestamp, order: .reverse) private var nonBioRecords: [LocalScanRecord]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Binding var isInsightSheetOpen: Bool
    
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var showDeleteConfirmation = false
    
// Layout abstracted into generic component
    
    var body: some View {
        ScrollView {
            if nonBioRecords.isEmpty {
                EmptyStateView(
                    iconName: "photo.on.rectangle.angled",
                    title: "No non-biological scans",
                    message: "You haven't documented any non-biological subjects yet."
                )
            } else {
                ScanGridMatrix(scans: nonBioRecords, onSelect: { scan in
                    selectedScanForInsight = scan
                    inferenceEngine.load(from: scan)
                }, onDelete: { scan in
                    scanToDelete = scan
                    showDeleteConfirmation = true
                })
            }
        }
        .navigationTitle("Non-biological")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedScanForInsight) { scan in
            InsightSheetView(isPresented: Binding(
                get: { selectedScanForInsight != nil },
                set: { if !$0 { selectedScanForInsight = nil } }
            ))
        }
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            record: scanToDelete,
            modelContext: modelContext
        ) {
            scanToDelete = nil
        }
    }
}
