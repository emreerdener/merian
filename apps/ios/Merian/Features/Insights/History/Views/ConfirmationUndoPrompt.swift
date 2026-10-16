import SwiftUI

/// Captures the exact displayed action; no operation is created before confirmation.
private struct ConfirmationUndoPrompt: ViewModifier {
    @Binding var action: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert("Undo your species identification?", isPresented: Binding(
            get: { action != nil }, set: { if !$0 { action = nil } }
        )) {
            Button("Undo confirmation") {
                let confirmedAction = action
                action = nil
                confirmedAction?()
            }
            Button("Cancel", role: .cancel) { action = nil }
        } message: {
            Text("Your correction will be removed and the original AI identification will return as unreviewed. The current selection will not change.")
        }
    }
}

extension View {
    func confirmationUndoPrompt(action: Binding<(() -> Void)?>) -> some View {
        modifier(ConfirmationUndoPrompt(action: action))
    }
}
