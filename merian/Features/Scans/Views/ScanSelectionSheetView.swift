import SwiftUI
import SwiftData

struct ScanSelectionSheetView: View {
    @Bindable var collection: ScanCollection
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .ignoresSafeArea()
                
                ScrollView {
                    if allRecords.isEmpty {
                        VStack {
                            Spacer().frame(height: 80)
                            Text("No Scans in Library")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(allRecords) { scan in
                                let isSelected = collection.scans?.contains(where: { $0.id == scan.id }) ?? false
                                
                                Button(action: {
                                    toggleSelection(scan: scan)
                                }) {
                                    Group {
                                        ScansThumbnailView(imagePath: scan.localImagePath, fallbackImageUrl: scan.referenceImageUrl)
                                    }
                                    .overlay(
                                        ZStack {
                                            if isSelected {
                                                Color.blue.opacity(0.6)
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 24))
                                            }
                                        }
                                    )
                                }
                            }
                        }
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
    }
    
    private func toggleSelection(scan: LocalScanRecord) {
        if let existingScans = collection.scans, let index = existingScans.firstIndex(where: { $0.id == scan.id }) {
            collection.scans?.remove(at: index)
        } else {
            if collection.scans == nil {
                collection.scans = []
            }
            collection.scans?.append(scan)
        }
        try? modelContext.save()
    }
}
