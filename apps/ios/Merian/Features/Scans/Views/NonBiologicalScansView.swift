import SwiftData
import SwiftUI

struct NonBiologicalScansView: View {
    // MARK: - State Dependencies
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == false }, sort: \.timestamp, order: .reverse) private var nonBioRecords: [LocalScanRecord]
    
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Interface State
    @State private var scanToRescue: String?
    @State private var scanToDelete: String?
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
                    scanToRescue = scan.id
                }, onDelete: { scan in
                    scanToDelete = scan.id
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
        .task {
            await purgeExpiredNonBiologicalScans()
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
                if let scanId = scanToRescue {
                    markAsBiological(scanId: scanId)
                }
            }
        } message: {
            Text("This will move the scan back into your main library and prevent it from being auto-deleted.")
        }
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            scanId: scanToDelete,
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
    private func purgeExpiredNonBiologicalScans() async {
        await AppDIContainer.shared.scanRepository.purgeExpiredNonBiologicalScans(
            modelContainer: modelContext.container
        )
    }

    private func clearAllNonBiologicalScans() {
        isClearingAll = true
        let payloads = nonBioRecords.map { scan in
            let paths = scan.capturedMediaSnapshot.imagePaths
            return BackgroundDatabaseActor.ScanErasurePayload(id: scan.id, imagePaths: paths)
        }
        let container = modelContext.container
        
        DetachedWork.fireAndForget(
            priority: .userInitiated,
            category: .backgroundDatabaseMutation
        ) {
            let backgroundActor = BackgroundDatabaseActor(modelContainer: container)

            do {
                let deletedPaths = try await backgroundActor.bulkDeleteNonBiologicalScans(payloads: payloads)
                await FileIOActor.shared.deleteImages(at: deletedPaths)

                await MainActor.run {
                    isClearingAll = false
                    ScanLibraryEvents.postLibraryDidUpdate()
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
        markAsBiological(scanId: scan.id)
    }

    private func markAsBiological(scanId: String) {
        // Local Optimistic UI - Re-fetch explicitly on the MainActor context to guarantee SwiftData UI observers fire!
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let activeRecord = try? modelContext.fetch(descriptor).first else {
            MerianLog.data.error("Failed to re-fetch scan for mutation.")
            return
        }
        
        activeRecord.normalizeForBiologicalRescue()
        
        do {
            try modelContext.save()
            ScanLibraryEvents.postLibraryDidUpdate()
            MerianLog.data.debug("Scan rescued back to biological library.")
        } catch {
            MerianLog.data.error("SwiftData save failed during biological rescue: \(error, privacy: .private)")
        }
        
        // Remote synchronization belongs in the repository layer so the view only initiates intent.
        Task {
            await AppDIContainer.shared.scanRepository.syncBiologicalRescue(scanId: scanId)
        }
        
        AppEventPublisher.shared.send(.triggerRefinement(
            scanId: scanId,
            initialDescription: LocalScanRecord.biologicalRescueReanalysisPrompt
        ))
        HapticManager.shared.triggerSelectionPulse()
        withAnimation { toastMessage = "Restored for reanalysis" }
    }
}
