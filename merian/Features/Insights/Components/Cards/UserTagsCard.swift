import SwiftData
import SwiftUI

struct UserTagsCard: View {
    let scanId: String
    
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [LocalScanRecord]
    
    @State private var showingAddTagAlert = false
    @State private var newTagText = ""
    
    init(scanId: String) {
        self.scanId = scanId
        self._records = Query(filter: #Predicate<LocalScanRecord> { $0.id == scanId })
    }
    
    var record: LocalScanRecord? {
        records.first
    }
    
    var body: some View {
        if let record = record {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundColor(.secondary)
                    Text("Tags")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        newTagText = ""
                        showingAddTagAlert = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .imageScale(.large)
                            .foregroundColor(.accentColor)
                    }
                }
                
                if record.customTags.isEmpty {
                    Text("No custom tags added. Add tags to easily find this scan later.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(record.customTags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                        .font(.subheadline)
                                    
                                    Button {
                                        removeTag(tag, from: record)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary.opacity(0.8))
                                            .imageScale(.small)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .card()
            .alert("Add Tag", isPresented: $showingAddTagAlert) {
                TextField("e.g. backyard, summer", text: $newTagText)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    addTag(newTagText, to: record)
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Add a custom tag to easily search for this scan later.")
            }
        }
    }
    
    // MARK: - Mutable Logic
    private func addTag(_ tag: String, to record: LocalScanRecord) {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !record.customTags.contains(trimmed) else { return }
        
        record.customTags.append(trimmed)
        try? modelContext.save()
        syncTagsToCloud(record: record)
        NotificationCenter.default.post(name: NSNotification.Name("ScanRequiresSearchIndexUpdate"), object: nil, userInfo: ["scanId": record.id])
    }
    
    private func removeTag(_ tag: String, from record: LocalScanRecord) {
        record.customTags.removeAll { $0 == tag }
        try? modelContext.save()
        syncTagsToCloud(record: record)
        NotificationCenter.default.post(name: NSNotification.Name("ScanRequiresSearchIndexUpdate"), object: nil, userInfo: ["scanId": record.id])
    }
    
    // MARK: - Cloud Sync
    private func syncTagsToCloud(record: LocalScanRecord) {
        let tags = record.customTags
        let scanId = record.id
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        Task(priority: .background) {
            do {
                try await SupabaseManager.shared.client
                    .from("scans")
                    .update(["custom_tags": tags])
                    .eq("id", value: scanId)
                    .execute()
            } catch {
                MerianLog.data.error("🚨 UserTagsCard: Failed to sync tags to cloud: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
