import SwiftUI

enum ProSettingsStyle {
    static let accent = Color(red: 0.12, green: 0.65, blue: 0.45)
}

struct ProSettingsBanner: View {
    let isProActive: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image("bird-tree")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .scaleEffect(x: -1, y: 1)
                .offset(x: -14)
                .padding(.leading, 14)
                .padding(.vertical, -18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(PublicBrand.name)
                        .font(.system(.title2).weight(.bold))
                        .foregroundStyle(.white)
                    Text("PRO")
                        .font(.system(.title3).weight(.black))
                        .foregroundStyle(ProSettingsStyle.accent)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.78)

                Text(
                    isProActive
                        ? "Your advanced field kit is active"
                        : "Unlock richer captures and advanced AI analysis"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(.trailing, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.11, blue: 0.08),
                    Color(red: 0.04, green: 0.31, blue: 0.20),
                    Color(red: 0.05, green: 0.20, blue: 0.16)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isProActive ? "Naturebook Pro active" : "Naturebook Pro"
        )
    }
}

struct ProFeatureToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let icon: String
    let iconColor: Color
    let isProActive: Bool
    let onUpgrade: () -> Void

    var body: some View {
        if isProActive {
            SettingsToggleRow(
                title: title,
                description: description,
                isOn: $isOn,
                icon: icon,
                iconColor: iconColor
            )
        } else {
            Button(action: onUpgrade) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .foregroundStyle(iconColor)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)

                        Text(title)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("Upgrade")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ProSettingsStyle.accent)

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 36)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
