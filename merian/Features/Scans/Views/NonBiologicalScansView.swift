import SwiftUI
import SwiftData

struct NonBiologicalScansView: View {
    // MARK: - State Dependencies
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == false || $0.commonName == "Unknown Subject" }, sort: \.timestamp, order: .reverse) private var nonBioRecords: [LocalScanRecord]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) var inferenceEngine
    @Binding var isInsightSheetOpen: Bool
    
    // MARK: - Interface State
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var showDeleteConfirmation = false
    
    // MARK: - View Layout
    
    var body: some View {
        ScrollView {
            if nonBioRecords.isEmpty {
                EmptyStateView(
                    iconName: "photo.on.rectangle.angled",
                    title: "No non-biological scans",
                    message: "You haven't documented any non-biological subjects yet."
                )
            } else {
                ScansGrid(scans: nonBioRecords, onSelect: { scan in
                    selectedScanForInsight = scan
                    inferenceEngine.load(from: scan)
                }, onDelete: { scan in
                    scanToDelete = scan
                    showDeleteConfirmation = true
                })
            }
        }
        
        // MARK: - View Modifiers
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
