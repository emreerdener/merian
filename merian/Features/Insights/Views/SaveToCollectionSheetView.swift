import SwiftUI
import SwiftData

struct SaveToCollectionSheetView: View {
    let scanId: String
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \ScanCollection.createdAt, order: .reverse) private var collections: [ScanCollection]
    
    @State private var localRecord: LocalScanRecord?
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                if localRecord == nil {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            Button(action: {
                                showNewCollectionAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 20))
                                    Text("New Collection")
                                        .font(.body)
                                    Spacer()
                                }
                                .padding()
                                .foregroundColor(.blue)
                                .background(Color(UIColor.tertiarySystemFill))
                            }
                            
                            Divider().background(Color(UIColor.separator))
                            
                            ForEach(collections) { collection in
                                let isInCollection = collection.scans?.contains(where: { $0.id == scanId }) ?? false
                                
                                Button(action: {
                                    toggleCollection(collection: collection)
                                }) {
                                    HStack {
                                        Image(systemName: "folder")
                                            .font(.system(size: 20))
                                            .foregroundColor(.secondary)
                                            .frame(width: 24)
                                        
                                        Text(collection.name)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if isInCollection {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 20))
                                        }
                                    }
                                    .padding()
                                    .background(Color(UIColor.tertiarySystemFill))
                                }
                                Divider().background(Color(UIColor.separator))
                            }
                        }
                        .cornerRadius(12)
                        .padding()
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                }
            }
            .alert("New Collection", isPresented: $showNewCollectionAlert) {
                TextField("Collection Name", text: $newCollectionName)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
                Button("Create") {
                    let collection = ScanCollection(name: newCollectionName.isEmpty ? "Untitled" : newCollectionName)
                    modelContext.insert(collection)
                    
                    if let record = localRecord {
                        if collection.scans == nil {
                            collection.scans = []
                        }
                        collection.scans?.append(record)
                    }
                    
                    try? modelContext.save()
                    newCollectionName = ""
                }
            } message: {
                Text("Enter a name for this new collection.")
            }
        }
        .onAppear {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            localRecord = try? modelContext.fetch(descriptor).first
        }
    }
    
    private func toggleCollection(collection: ScanCollection) {
        guard let record = localRecord else { return }
        
        if let existingScans = collection.scans, let index = existingScans.firstIndex(where: { $0.id == record.id }) {
            collection.scans?.remove(at: index)
        } else {
            if collection.scans == nil {
                collection.scans = []
            }
            collection.scans?.append(record)
        }
        try? modelContext.save()
    }
}
