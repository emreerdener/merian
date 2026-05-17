import SwiftData
import SwiftUI

struct UserTagsCard: View {
    let scanId: String
    
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [LocalScanRecord]
    
    @State private var showingAddTagAlert = false
    @State private var newTagText = ""
    @State private var tagMutationErrorMessage: String?
    
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
                InsightCardHeader(systemImage: "tag", title: "Tags") {
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
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No custom tags added. Add tags to easily find this scan later.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button {
                            newTagText = ""
                            showingAddTagAlert = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Add tag")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
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

                if let tagMutationErrorMessage {
                    Text(tagMutationErrorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
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
        guard persistTagMutation(logContext: "add custom tag") else { return }
        syncTagsToCloud(record: record)
        ScanLibraryEvents.postSearchIndexUpdate(scanId: record.id)
    }
    
    private func removeTag(_ tag: String, from record: LocalScanRecord) {
        guard record.customTags.contains(tag) else { return }
        record.customTags.removeAll { $0 == tag }
        guard persistTagMutation(logContext: "remove custom tag") else { return }
        syncTagsToCloud(record: record)
        ScanLibraryEvents.postSearchIndexUpdate(scanId: record.id)
    }

    @discardableResult
    private func persistTagMutation(logContext: String) -> Bool {
        do {
            try modelContext.save()
            tagMutationErrorMessage = nil
            return true
        } catch {
            modelContext.rollback()
            tagMutationErrorMessage = "Tag changes could not be saved."
            MerianLog.data.error("UserTagsCard: failed to save \(logContext, privacy: .public): \(error, privacy: .private)")
            return false
        }
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
