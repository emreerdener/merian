import SwiftUI

struct FieldNotesTextEditor: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
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
                .focused(isFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if text.isEmpty {
                Text("Write down what you noticed...")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }
        }
        // Collapse before the keyboard arrives so its avoidance pass does not
        // translate the editor beneath the navigation bar on first focus.
        .frame(
            maxWidth: .infinity,
            minHeight: 320,
            maxHeight: isFocused.wrappedValue ? 320 : .infinity,
            alignment: .topLeading
        )
        .layoutPriority(1)
        .contentShape(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .onTapGesture {
            isFocused.wrappedValue = true
        }
    }
}
