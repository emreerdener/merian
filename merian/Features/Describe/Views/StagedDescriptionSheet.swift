import SwiftUI

// MARK: - Staged Description Sheet
// Lets the user view, edit, or remove an ObservationContext that was staged
// alongside images for a combined multi-modal submission. Operates on a local
// draft copy so edits never touch the Describe page's root observationContext binding.

struct StagedDescriptionSheet: View {
    let initialText: String
    let onSave: (String) -> Void
    let onRemove: () -> Void

    @State private var draftText: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    init(initialText: String, onSave: @escaping (String) -> Void, onRemove: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onRemove = onRemove
        self._draftText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))

                    TextField("Describe what you saw...", text: $draftText, axis: .vertical)
                        .lineLimit(5...10)
                        .font(.body)
                        .focused($isFocused)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .onTapGesture { isFocused = true }

                Button(role: .destructive) {
                    onRemove()
                    dismiss()
                } label: {
                    Label("Remove description", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isFocused = false
                    }
            )
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draftText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFocused = false
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
