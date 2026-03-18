import SwiftUI
import SwiftData

struct NonBiologicalScansView: View {
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == false }, sort: \.timestamp, order: .reverse) private var nonBioRecords: [LocalScanRecord]
    
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
                VStack(spacing: 16) {
                    Spacer().frame(height: 80)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary)
                    Text("No non-biological scans")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("You haven't documented any non-biological subjects yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
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
        .navigationTitle("Non biological")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedScanForInsight) { scan in
            InsightSheetView(isPresented: Binding(
                get: { selectedScanForInsight != nil },
                set: { if !$0 { selectedScanForInsight = nil } }
            ))
        }
        .confirmationDialog(
            "Delete scan",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
            presenting: scanToDelete
        ) { scan in
            Button("Delete scan permanently", role: .destructive) {
                HapticManager.shared.triggerErrorThump()
                ScanRepository.shared.eradicateScan(record: scan, modelContext: modelContext)
                scanToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                scanToDelete = nil
            }
        } message: { _ in
            Text("Are you sure you want to delete this scan? This will permanently remove the photo and data from your device.")
        }
    }
}
