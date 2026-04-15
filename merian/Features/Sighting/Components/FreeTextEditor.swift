import SwiftUI

struct FreeTextEditor: View {
    @Binding var text: String
    let maxLength: Int
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isFocused.wrappedValue ? Color.white.opacity(0.3) : Color.white.opacity(0.12),
                                lineWidth: 0.5
                            )
                    )

                if text.isEmpty {
                    Text("e.g. had distinctive orange spots on its wings…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: Binding(
                    get: { text },
                    set: { text = String($0.prefix(maxLength)) }
                ))
                .font(.subheadline)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(minHeight: 90, maxHeight: 140)
                .focused(isFocused)
            }

            Text("\(text.count)/\(maxLength)")
                .font(.caption2)
                .foregroundStyle(text.count >= maxLength ? .orange : .white.opacity(0.3))
                .animation(.easeInOut(duration: 0.15), value: text.count >= maxLength)
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused.wrappedValue)
    }
}
