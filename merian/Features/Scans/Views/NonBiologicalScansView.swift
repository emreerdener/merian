import SwiftUI
import SwiftData

struct NonBiologicalScansView: View {
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == false || $0.commonName == "Unknown subject" }, sort: \.timestamp, order: .reverse) private var nonBioRecords: [LocalScanRecord]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Binding var isInsightSheetOpen: Bool
    
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var showDeleteConfirmation = false
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            if nonBioRecords.isEmpty {
                EmptyStateView(
                    iconName: "photo.on.rectangle.angled",
                    title: "No non-biological scans",
                    message: "You haven't documented any non-biological subjects yet."
                )
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(nonBioRecords) { scan in
                        Button(action: {
                            selectedScanForInsight = scan
                            inferenceEngine.load(from: scan)
                        }) {
                            Group {
                                ScansThumbnailView(imagePath: scan.localImagePath, fallbackImageUrl: scan.referenceImageUrl)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                scanToDelete = scan
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete scan permanently", systemImage: "trash")
                            }
                        }
                    }
                }
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
            scanId: scanToDelete?.id,
            modelContext: modelContext
        ) {
            scanToDelete = nil
        }
    }
}
