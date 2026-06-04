import SwiftData
import SwiftUI

struct ScanDeletionDialogModifier: ViewModifier {
    // MARK: - State Dependencies
    @Binding var isPresented: Bool
    
    // MARK: - Context Dependencies
    let scanId: String?
    let modelContext: ModelContext
    
    // MARK: - Callbacks
    let onComplete: () -> Void

    // MARK: - Modifier Layout
    func body(content: Content) -> some View {
        content
            .alert(
                "Delete scan?",
                isPresented: $isPresented
            ) {
                Button("Delete permanently", role: .destructive) {
                    guard let scanId else { return }
                    var descriptor = FetchDescriptor<LocalScanRecord>(
                        predicate: #Predicate { $0.id == scanId }
                    )
                    descriptor.fetchLimit = 1
                    guard let activeRecord = try? modelContext.fetch(descriptor).first else {
                        onComplete()
                        return
                    }
                    HapticManager.shared.triggerErrorThump()
                    AppDIContainer.shared.scanRepository.eradicateScan(record: activeRecord, modelContext: modelContext)
                    onComplete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the discovery and all associated visuals from your history.")
            }
    }
}

// MARK: - View Extensions

extension View {
    func scanDeletionDialog(
        isPresented: Binding<Bool>,
        scanId: String?,
        modelContext: ModelContext,
        onComplete: @escaping () -> Void = {}
    ) -> some View {
        self.modifier(ScanDeletionDialogModifier(
            isPresented: isPresented,
            scanId: scanId,
            modelContext: modelContext,
            onComplete: onComplete
        ))
    }
}
