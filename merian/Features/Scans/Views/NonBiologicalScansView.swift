import SwiftData
import SwiftUI

struct NonBiologicalScansView: View {
    // MARK: - State Dependencies
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == false }, sort: \.timestamp, order: .reverse) private var nonBioRecords: [LocalScanRecord]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) var inferenceEngine
    @Binding var isInsightSheetOpen: Bool
    
    // MARK: - Interface State
    @State private var scanToRescue: LocalScanRecord?
    @State private var scanToDelete: LocalScanRecord?
    @State private var showDeleteConfirmation = false
    @State private var showClearAllConfirmation = false
    @State private var isClearingAll = false
    @State private var toastMessage: String?
    
    // MARK: - View Layout
    
    var body: some View {
        ScrollView {
            if nonBioRecords.isEmpty {
                EmptyStateView(
                    iconName: "photo.on.rectangle.angled",
                    title: "Empty",
                    message: "This collection is currently empty. Non-biological items are automatically purged here after 30 days."
                )
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.red)
                        .font(.system(size: 18))
                    
                    Text("Items in this collection are permanently deleted after 30 days to free up space.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                ScansGrid(scans: nonBioRecords, onSelect: { scan in
                    scanToRescue = scan
                }, onDelete: { scan in
                    scanToDelete = scan
                    showDeleteConfirmation = true
                }) { scan in
                    Button {
                        markAsBiological(scan)
                    } label: {
                        Label("Mark as biological", systemImage: "leaf.arrow.triangle.circlepath")
                    }
                }
            }
        }
        .overlay {
            if isClearingAll {
                ProgressView("Clearing scans...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = toastMessage {
                ToastBanner(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toastMessage = nil
                    }
                }) {
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .task(id: toastMessage) {
            guard toastMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                toastMessage = nil
            }
        }
        
        // MARK: - View Modifiers
        .navigationTitle("Non-biological")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !nonBioRecords.isEmpty {
                    Button(action: {
                        showClearAllConfirmation = true
                    }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .buttonBorderShape(.circle)
                }
            }
        }
        .alert(
            "Mark this item as biological?",
            isPresented: Binding(
                get: { scanToRescue != nil },
                set: { if !$0 { scanToRescue = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Mark as biological") {
                if let scan = scanToRescue {
                    markAsBiological(scan)
                }
            }
        } message: {
            Text("This will move the scan back into your main library and prevent it from being auto-deleted.")
        }
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            record: scanToDelete,
            modelContext: modelContext
        ) {
            scanToDelete = nil
            withAnimation { toastMessage = "Scan deleted" }
        }
        .alert(
            "Delete \(nonBioRecords.count) non-biological scans?",
            isPresented: $showClearAllConfirmation
        ) {
            Button("Delete all", role: .destructive) {
                clearAllNonBiologicalScans()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Action Handlers
    private func clearAllNonBiologicalScans() {
        isClearingAll = true
        let payloads = nonBioRecords.map { scan in
            let paths = scan.capturedMediaSnapshot.imagePaths
            return BackgroundDatabaseActor.ScanErasurePayload(id: scan.id, imagePaths: paths)
        }
        let container = modelContext.container
        
        Task.detached(priority: .userInitiated) {
            let backgroundActor = BackgroundDatabaseActor(modelContainer: container)

            do {
                let deletedPaths = try await backgroundActor.bulkDeleteNonBiologicalScans(payloads: payloads)
                await FileIOActor.shared.deleteImages(at: deletedPaths)

                await MainActor.run {
                    isClearingAll = false
                    HapticManager.shared.triggerSuccessPulse()
                    withAnimation { toastMessage = "Scans cleared" }
                    Task { await AppDIContainer.shared.offlineQueueManager.syncPendingDeletions() }
                }
            } catch {
                await MainActor.run {
                    isClearingAll = false
                    HapticManager.shared.triggerErrorThump()
                    withAnimation { toastMessage = "Couldn't clear scans" }
                }
            }
        }
    }
    
    private func markAsBiological(_ scan: LocalScanRecord) {
        // Local Optimistic UI - Re-fetch explicitly on the MainActor context to guarantee SwiftData UI observers fire!
        guard let activeRecord = modelContext.model(for: scan.persistentModelID) as? LocalScanRecord else {
            MerianLog.data.error("Failed to re-fetch scan for mutation.")
            return
        }
        
        activeRecord.isBiological = true
        activeRecord.ecologyType = "unknown"
        activeRecord.aiReasoning = nil
        
        do {
            try modelContext.save()
            MerianLog.data.debug("Scan rescued back to biological library.")
        } catch {
            MerianLog.data.error("SwiftData save failed during biological rescue: \(error, privacy: .private)")
        }
        
        let scanId = activeRecord.id
        // Remote Synchronization
        Task.detached {
            struct BiologicalOverridePayload: Encodable, Sendable {
                let is_biological_subject: Bool
                let ecology_type: String
            }
            let payload = BiologicalOverridePayload(is_biological_subject: true, ecology_type: "unknown")
            
            do {
                try await AppDIContainer.shared.supabaseManager.client.from("scans").update(payload).eq("id", value: scanId).execute()
            } catch {
                MerianLog.network.error("Remote markAsBiological sync failed: \(error, privacy: .private)")
            }
        }
        
        HapticManager.shared.triggerSelectionPulse()
        withAnimation { toastMessage = "Restored to library" }
    }
}
