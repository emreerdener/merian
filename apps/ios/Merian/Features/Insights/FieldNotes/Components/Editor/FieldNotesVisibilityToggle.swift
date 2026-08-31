import SwiftUI

struct FieldNotesVisibilityToggle: View {
    @Binding var isPublic: Bool
    let hasNotes: Bool
    let isSaving: Bool
    let detailText: String

    var body: some View {
        Toggle(isOn: $isPublic) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show on Explore")
                    .font(.subheadline.weight(.semibold))

                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .disabled(!hasNotes || isSaving)
        .padding(12)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
