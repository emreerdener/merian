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
        .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
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

    private var shadowColor: Color {
        switch style {
        case .primary:
            .black.opacity(0.24)
        case .status:
            .clear
        }
    }
}
