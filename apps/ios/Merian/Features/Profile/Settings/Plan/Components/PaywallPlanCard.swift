import RevenueCat
import SwiftUI

struct PaywallPlanCard: View {
    let package: Package
    let isSelected: Bool
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: isCompact ? 8 : 14) {
                HStack(alignment: .top) {
                    Text(badgeText)
                        .font(
                            .system(
                                size: isCompact ? 10 : 12,
                                weight: .heavy
                            )
                        )
                        .foregroundStyle(accent)
                        .padding(.horizontal, isCompact ? 10 : 12)
                        .padding(.vertical, isCompact ? 5 : 7)
                        .background(accent.opacity(0.14), in: Capsule())

                    Spacer()

                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(
                        .system(
                            size: isCompact ? 20 : 25,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        isSelected
                            ? accent
                            : Color.secondary.opacity(0.45)
                    )
                }

                VStack(alignment: .leading, spacing: isCompact ? 4 : 7) {
                    Text(planName)
                        .font(
                            .system(
                                size: isCompact ? 28 : 34,
                                weight: .heavy
                            )
                        )
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(planDescription)
                        .font(
                            .system(
                                size: isCompact ? 15 : 18,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.secondary)
                        .lineSpacing(isCompact ? 2 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(package.paywallDisplayPrice)
                            .font(
                                .system(
                                    size: isCompact ? 24 : 28,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(.primary)
                        Text(priceSuffix)
                            .font(
                                .system(
                                    size: isCompact ? 15 : 18,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(.secondary)
                    }

                    Text(renewalText)
                        .font(
                            .system(
                                size: isCompact ? 12 : 14,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
            }
            .padding(.top, isCompact ? 14 : 18)
            .padding(.horizontal, isCompact ? 16 : 20)
            .padding(.bottom, isCompact ? 16 : 22)
            .frame(
                width: isCompact ? 280 : 310,
                height: isCompact ? 210 : 252
            )
            .background(
                LinearGradient(
                    colors: [
                        accent.opacity(isSelected ? 0.18 : 0.08),
                        Color(uiColor: .secondarySystemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 30,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        accent.opacity(isSelected ? 0.78 : 0.26),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accent: Color {
        if package.isSevenDayPassPlan { return .cyan }

        switch package.packageType {
        case .lifetime: return .pink
        case .monthly, .weekly: return .cyan
        default: return .mint
        }
    }

    private var badgeText: String {
        if package.isSevenDayPassPlan { return "NO SUBSCRIPTION" }
        if package.isAnnualPlan { return "SUBSCRIPTION" }

        switch package.packageType {
        case .monthly: return "SUBSCRIPTION"
        case .weekly: return "FIELD PASS"
        case .lifetime: return "NO SUBSCRIPTION"
        default: return "PRO"
        }
    }

    private var planName: String {
        if package.isSevenDayPassPlan { return "7 Day Pass" }
        if package.isAnnualPlan { return "Annual" }

        switch package.packageType {
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        case .lifetime: return "Lifetime"
        default:
            return package.storeProduct.localizedTitle
                .replacingOccurrences(of: "Naturebook", with: "")
                .replacingOccurrences(of: "Merian", with: "")
        }
    }

    private var planDescription: String {
        if package.isSevenDayPassPlan {
            return "Full Naturebook Pro access for 7 days."
        }
        if package.isAnnualPlan {
            return "The full Naturebook Pro experience for a year."
        }

        switch package.packageType {
        case .monthly:
            return "All Pro tools with month-to-month flexibility."
        case .weekly:
            return "A short pass for trips, classes, and field days."
        case .lifetime:
            return "Pay once and keep every Pro feature for life."
        default:
            return package.storeProduct.localizedDescription
        }
    }

    private var priceSuffix: String {
        if package.isSevenDayPassPlan { return "for 7 Days" }
        if package.isAnnualPlan { return "/ Year" }

        switch package.packageType {
        case .monthly: return "/ Month"
        case .weekly: return "/ Week"
        default: return ""
        }
    }

    private var renewalText: String {
        if package.isSevenDayPassPlan {
            return "One-time access. No subscription."
        }
        if package.isAnnualPlan {
            return "Plan auto-renews annually. Cancel anytime."
        }

        switch package.packageType {
        case .monthly:
            return "Plan auto-renews monthly. Cancel anytime."
        case .weekly:
            return "One week of Pro."
        case .lifetime:
            return "One-time purchase."
        default:
            return package.storeProduct.localizedDescription
        }
    }
}
