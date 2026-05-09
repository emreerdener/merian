import SwiftUI

/// Editable field-notes sheet presented from the insight flow.
struct FieldNotesSheet: View {
    @Binding var text: String
    let promptContext: FieldNotesPromptContext

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // MARK: - Text Field
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )

                            TextEditor(text: $text)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .focused($isTextFieldFocused)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)

                            if text.isEmpty {
                                Text("Write down what you noticed...")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onTapGesture {
                            isTextFieldFocused = true
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
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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

            if showDeleteConfirmation {
                clearNotesConfirmationOverlay
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .scrollDismissesKeyboard(.interactively)
    }

    private var clearNotesConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteConfirmation = false
                    }
                }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clear field notes?")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("This removes the notes from this scan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmation = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )

                    Button(role: .destructive) {
                        clearFieldNotes()
                    } label: {
                        Text("Clear")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.red)
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(10)
    }

    private func clearFieldNotes() {
        isTextFieldFocused = false
        text = ""
        showDeleteConfirmation = false
        dismiss()
    }
}
