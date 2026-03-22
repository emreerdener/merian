import SwiftUI
import SwiftData

struct ScanDeletionDialogModifier: ViewModifier {
    // MARK: - State Dependencies
    @Binding var isPresented: Bool
    
    // MARK: - Context Dependencies
    let record: LocalScanRecord?
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
                    guard let activeRecord = record else { return }
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
        record: LocalScanRecord?,
        modelContext: ModelContext,
        onComplete: @escaping () -> Void = {}
    ) -> some View {
        self.modifier(ScanDeletionDialogModifier(
            isPresented: isPresented,
            record: record,
            modelContext: modelContext,
            onComplete: onComplete
        ))
    }
}
