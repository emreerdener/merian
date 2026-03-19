import SwiftUI
import SwiftData

struct ScanDeletionDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let record: LocalScanRecord?
    let modelContext: ModelContext
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete scan",
                isPresented: $isPresented,
                titleVisibility: .visible
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
