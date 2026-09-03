import SwiftUI

struct FieldTripDetailPrimaryActionBar: View {
    enum Style {
        case primary
        case status
    }

    let title: String
    let systemImage: String?
    var isLoading = false
    var isEnabled = true
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(foregroundColor)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                    }

                    Text(title)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)
            }
            .font(.headline)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(backgroundColor)
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "In progress" : "")
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            .white
        case .status:
            .secondary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            .accentColor
        case .status:
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}
