import SwiftUI

/// A reusable row for settings items that navigate or trigger an action.
struct SettingsNavigationRow: View {
    let title: String
    var description: String?
    var icon: String?
    var iconColor: Color = .gray

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 24)
                }
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .semibold))
            }
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, icon != nil ? 36 : 0)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A reusable row wrapping a Toggle with an optional icon and caption.
struct SettingsToggleRow: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool
    var icon: String?
    var iconColor: Color = .gray

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 12) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(iconColor)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                    }
                    Text(title)
                }
            }
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, icon != nil ? 36 : 0)
            }
        }
        .padding(.vertical, 4)
    }
}
