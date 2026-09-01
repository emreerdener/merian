import SwiftUI

struct ReadyConsentToggleRow: View {
    @Binding var isOn: Bool
    let statement: AttributedString
    let accessibilityLabel: String
    let accessibilityHint: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: $isOn) {
                EmptyView()
            }
            .labelsHidden()
            .tint(.accentColor)
            .fixedSize()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityIdentifier(accessibilityIdentifier)

            Text(statement)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
