import SwiftUI

/// Editable field-notes sheet presented from the insight flow.
struct FieldNotesSheet: View {
    @Binding var text: String
    let promptContext: FieldNotesPromptContext

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: - Text Field
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))

                        TextField(
                            "Write down what you noticed in the field...",
                            text: $text,
                            axis: .vertical
                        )
                        .lineLimit(8...16)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .focused($isTextFieldFocused)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isTextFieldFocused = false
                    }
            )
            .navigationTitle("Field notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive, action: { 
                            if isTextFieldFocused {
                                isTextFieldFocused = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    showDeleteConfirmation = true
                                }
                            } else {
                                showDeleteConfirmation = true
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextFieldFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .scrollDismissesKeyboard(.interactively)
        .alert("Clear field notes?", isPresented: $showDeleteConfirmation) {
            Button("Clear notes", role: .destructive) {
                text = ""
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete these notes? This cannot be undone.")
        }
    }
}
