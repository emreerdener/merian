import SwiftUI

struct DescribeTextEditorView: View {
    let placeholder: String
    @Binding var text: String
    let focus: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            focus.wrappedValue
                                ? Color.primary.opacity(0.3)
                                : Color.primary.opacity(0.12),
                            lineWidth: 0.5
                        )
                )

            VStack(spacing: 0) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .id(placeholder)
                    .accessibilityLabel(placeholder)
                    .accessibilityIdentifier("DescribeTextInput")
                    .lineLimit(5...10)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .focused(focus)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 160, maxHeight: .infinity)
        .layoutPriority(1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            focus.wrappedValue = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DescribeTextArea")
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
}
