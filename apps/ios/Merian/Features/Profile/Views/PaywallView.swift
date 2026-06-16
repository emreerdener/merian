import RevenueCat
import SwiftUI

private struct PaywallHeroSlide: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let subtitle: String
    let glowColor: Color
}

private struct PaywallFeatureComparison: Identifiable {
    let id = UUID()
    let title: String
    let freeValue: String
    let proValue: String
}

private let paywallHeroSlides = [
    PaywallHeroSlide(
        imageName: "pw_butterfly",
        title: "Unlimited field scans",
        subtitle: "Keep identifying without daily scan limits.",
        glowColor: .mint
    ),
    PaywallHeroSlide(
        imageName: "pw_hawk",
        title: "Pro AI vision",
        subtitle: "Use Merian's most capable model for deeper analysis.",
        glowColor: .orange
    ),
    PaywallHeroSlide(
        imageName: "pw_bird",
        title: "Listen, compare, record",
        subtitle: "Unlock audio IDs, multi-capture context, and richer insight cards.",
        glowColor: .cyan
    )
]

private let paywallComparisons = [
    PaywallFeatureComparison(title: "Daily scans", freeValue: "1", proValue: "Unlimited"),
    PaywallFeatureComparison(title: "AI model", freeValue: "Flash", proValue: "Pro"),
    PaywallFeatureComparison(title: "Audio IDs", freeValue: "-", proValue: "Included"),
    PaywallFeatureComparison(title: "Multi-capture", freeValue: "-", proValue: "Included"),
    PaywallFeatureComparison(title: "Apple Watch logging", freeValue: "-", proValue: "Included")
]

struct PaywallView: View {
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackageIdentifier: String?
    @State private var selectedHeroIndex = 0
    @State private var heroCarouselAutoAdvanceDisabled = false
    @State private var isPurchasing = false
    @State private var isRestoring = false

    private var packages: [Package] {
        (revenueCatManager.currentOfferings?.current?.availablePackages ?? [])
            .sorted { packageSortRank($0) < packageSortRank($1) }
    }

    private var selectedPackage: Package? {
        if let selectedPackageIdentifier,
           let package = packages.first(where: { $0.identifier == selectedPackageIdentifier }) {
            return package
        }

        return preferredPackage(from: packages)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    brandHeader
                        .padding(.top, 28)

                    planPicker

                    heroCarousel
                        .padding(.horizontal, -20)

                    comparisonSection

                    memberSupportedSection

                    footerActions
                        .padding(.top, 4)
                        .padding(.bottom, 132)
                }
                .padding(.horizontal, 20)
            }
            .safeAreaInset(edge: .bottom) {
                stickyPurchaseBar
            }
        }
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .presentationDragIndicator(.visible)
        .task {
            if revenueCatManager.currentOfferings == nil {
                await revenueCatManager.fetchOfferings()
            }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: packages.map(\.identifier)) { _, _ in
            selectDefaultPackageIfNeeded()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 6) {
            Text("Merian")
                .font(.system(size: 20, weight: .bold))
            Text("PRO")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private var heroCarousel: some View {
        TabView(selection: $selectedHeroIndex) {
            ForEach(Array(paywallHeroSlides.enumerated()), id: \.element.id) { index, slide in
                PaywallHeroSlideView(slide: slide)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 356)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in
                    disableHeroCarouselAutoAdvance()
                }
        )
        .task(id: heroCarouselAutoAdvanceDisabled) {
            await autoAdvanceHeroCarousel()
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 7) {
                ForEach(paywallHeroSlides.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedHeroIndex ? Color.primary : Color.secondary.opacity(0.26))
                        .frame(width: index == selectedHeroIndex ? 20 : 7, height: 7)
                        .animation(.snappy(duration: 0.2), value: selectedHeroIndex)
                }
            }
            .padding(.bottom, 4)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var planPicker: some View {
        if revenueCatManager.isFetchingOfferings && packages.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.accentColor)
                Text("Loading Pro plans...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            )
        } else if packages.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "leaf.circle")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.mint)

                Text("Plans are unavailable right now.")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Please check your connection or try restoring an existing purchase.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .padding(.horizontal, 22)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(packages) { package in
                            PaywallPlanCard(
                                package: package,
                                isSelected: package.identifier == selectedPackage?.identifier
                            ) {
                                selectedPackageIdentifier = package.identifier
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -20)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("Feature")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 4) {
                        Text("YOUR PLAN")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.secondary)
                        Text("FREE")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 72)

                    Text("PRO")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.mint)
                        .frame(width: 72)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()
                    .padding(.leading, 16)

                ForEach(Array(paywallComparisons.enumerated()), id: \.element.id) { index, comparison in
                    PaywallComparisonRow(comparison: comparison)

                    if index < paywallComparisons.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memberSupportedSection: some View {
        VStack(spacing: 18) {
            Text("Member supported")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.primary)

            Image("pw_heron")
                .resizable()
                .scaledToFit()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .shadow(color: .mint.opacity(0.26), radius: 28, y: 16)

            Text("Pro keeps Merian moving: better models, richer ecological context, and field tools that work where discovery happens.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaywallFooterButton(icon: "arrow.clockwise", title: isRestoring ? "Restoring..." : "Restore Purchases") {
                Task { await tryRestore() }
            }
            .disabled(isRestoring)

            PaywallFooterButton(icon: "giftcard", title: "Redeem Code") {
                Purchases.shared.presentCodeRedemptionSheet()
            }

            Link(destination: URL(string: "https://merian.earth/privacy")!) {
                PaywallFooterLabel(icon: "hand.raised", title: "Privacy Policy")
            }

            Link(destination: URL(string: "https://merian.earth/terms")!) {
                PaywallFooterLabel(icon: "signature", title: "Terms of Use")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var stickyPurchaseBar: some View {
        VStack(spacing: 10) {
            Button {
                Task { await purchaseSelectedPackage() }
            } label: {
                VStack(spacing: 3) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(purchaseButtonTitle)
                            .font(.system(size: 18, weight: .bold))
                        Text(purchaseButtonSubtitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .background(
                    LinearGradient(
                        colors: selectedPackage == nil
                            ? [Color.secondary.opacity(0.26), Color.secondary.opacity(0.16)]
                            : [Color(red: 0.10, green: 0.62, blue: 0.74), Color(red: 0.13, green: 0.78, blue: 0.54)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(selectedPackage == nil ? 0.08 : 0.18), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.34), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(selectedPackage == nil || isPurchasing)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var purchaseButtonTitle: String {
        guard let selectedPackage else { return "Plans Unavailable" }

        if selectedPackage.isSevenDayPassPlan {
            return "Start 7-Day Pass"
        }

        switch selectedPackage.packageType {
        case .lifetime: return "Get Pro Lifetime"
        case .weekly: return "Start 7-Day Pass"
        default: return "Start Merian Pro"
        }
    }

    private var purchaseButtonSubtitle: String {
        guard let selectedPackage else { return "Check back soon or restore purchases" }

        let price = selectedPackage.storeProduct.localizedPriceString
        if selectedPackage.isSevenDayPassPlan {
            return "\(price) for 7 days."
        }

        switch selectedPackage.packageType {
        case .annual: return "\(price) per year. Cancel anytime."
        case .monthly: return "\(price) per month. Cancel anytime."
        case .weekly: return "\(price) for one week."
        case .lifetime: return "\(price) one-time purchase."
        default: return price
        }
    }

    private func selectDefaultPackageIfNeeded() {
        guard selectedPackageIdentifier == nil else { return }
        selectedPackageIdentifier = preferredPackage(from: packages)?.identifier
    }

    private func preferredPackage(from packages: [Package]) -> Package? {
        packages.first(where: \.isSevenDayPassPlan)
            ?? packages.first(where: { $0.packageType == .annual })
            ?? packages.first(where: { $0.packageType == .monthly })
            ?? packages.first
    }

    private func packageSortRank(_ package: Package) -> Int {
        if package.isSevenDayPassPlan { return 0 }

        switch package.packageType {
        case .annual: return 1
        case .monthly: return 2
        case .lifetime: return 3
        default: return 4
        }
    }

    @MainActor
    private func autoAdvanceHeroCarousel() async {
        guard !heroCarouselAutoAdvanceDisabled, paywallHeroSlides.count > 1 else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }

            guard !Task.isCancelled, !heroCarouselAutoAdvanceDisabled else { return }

            withAnimation(.easeInOut(duration: 0.35)) {
                selectedHeroIndex = (selectedHeroIndex + 1) % paywallHeroSlides.count
            }
        }
    }

    @MainActor
    private func disableHeroCarouselAutoAdvance() {
        heroCarouselAutoAdvanceDisabled = true
    }

    private func tryRestore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await revenueCatManager.restorePurchases()
            if revenueCatManager.isProActive {
                dismiss()
            }
        } catch {
            MerianLog.general.error("Purchase restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func purchaseSelectedPackage() async {
        guard let selectedPackage, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await revenueCatManager.purchase(selectedPackage)
            if revenueCatManager.isProActive {
                dismiss()
            }
        } catch {
            MerianLog.general.error("In-app purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct PaywallHeroSlideView: View {
    let slide: PaywallHeroSlide

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RadialGradient(
                    stops: [
                        .init(color: slide.glowColor.opacity(0.26), location: 0),
                        .init(color: slide.glowColor.opacity(0.12), location: 0.48),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center,
                    startRadius: 18,
                    endRadius: 134
                )
                    .frame(width: 350, height: 276)
                    .accessibilityHidden(true)

                Image(slide.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 184)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 10)
            }
            .frame(height: 228)
            .frame(maxWidth: .infinity)

            VStack(spacing: 7) {
                Text(slide.title)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.86)

                Text(slide.subtitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.bottom, 26)
    }
}

private struct PaywallPlanCard: View {
    let package: Package
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(badgeText)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(accent.opacity(0.14), in: Capsule())

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(planName)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(planDescription)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(package.storeProduct.localizedPriceString)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(priceSuffix)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(renewalText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .frame(width: 310, height: 252)
            .background(
                LinearGradient(
                    colors: [
                        accent.opacity(isSelected ? 0.18 : 0.08),
                        Color(uiColor: .secondarySystemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(accent.opacity(isSelected ? 0.78 : 0.26), lineWidth: isSelected ? 2 : 1)
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

        switch package.packageType {
        case .annual, .monthly: return "SUBSCRIPTION"
        case .weekly: return "FIELD PASS"
        case .lifetime: return "NO SUBSCRIPTION"
        default: return "PRO"
        }
    }

    private var planName: String {
        if package.isSevenDayPassPlan { return "7 Day Pass" }

        switch package.packageType {
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        case .lifetime: return "Lifetime"
        default: return package.storeProduct.localizedTitle.replacingOccurrences(of: "Merian", with: "")
        }
    }

    private var planDescription: String {
        if package.isSevenDayPassPlan {
            return "Full Merian Pro access for 7 days."
        }

        switch package.packageType {
        case .annual: return "The full Merian Pro experience for a year."
        case .monthly: return "All Pro tools with month-to-month flexibility."
        case .weekly: return "A short pass for trips, classes, and field days."
        case .lifetime: return "Pay once and keep every Pro feature for life."
        default: return package.storeProduct.localizedDescription
        }
    }

    private var priceSuffix: String {
        if package.isSevenDayPassPlan { return "for 7 Days" }

        switch package.packageType {
        case .annual: return "/ Year"
        case .monthly: return "/ Month"
        case .weekly: return "/ Week"
        default: return ""
        }
    }

    private var renewalText: String {
        if package.isSevenDayPassPlan { return "One-time access. No subscription." }

        switch package.packageType {
        case .annual: return "Plan auto-renews annually. Cancel anytime."
        case .monthly: return "Plan auto-renews monthly. Cancel anytime."
        case .weekly: return "One week of Pro."
        case .lifetime: return "One-time purchase."
        default: return package.storeProduct.localizedDescription
        }
    }
}

private extension Package {
    var isSevenDayPassPlan: Bool {
        if packageType == .weekly { return true }

        let searchableText = [
            identifier,
            storeProduct.localizedTitle,
            storeProduct.localizedDescription
        ]
            .joined(separator: " ")
            .lowercased()

        return searchableText.contains("7 day")
            || searchableText.contains("7-day")
            || searchableText.contains("seven day")
            || searchableText.contains("7_day")
            || (searchableText.contains("7") && searchableText.contains("pass"))
    }
}

private struct PaywallMiniMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .padding(.horizontal, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
        )
    }
}

private struct PaywallComparisonRow: View {
    let comparison: PaywallFeatureComparison

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(comparison.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            PaywallComparisonValue(value: comparison.freeValue, tint: .secondary)

            PaywallComparisonValue(value: comparison.proValue, tint: .mint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(comparison.title). Free: \(comparison.freeValue). Pro: \(comparison.proValue).")
    }
}

private struct PaywallComparisonValue: View {
    let value: String
    let tint: Color

    var body: some View {
        Group {
            if value == "Included" {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityLabel("Included")
            } else if value == "-" {
                Image(systemName: "minus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.58))
                    .accessibilityLabel("Not included")
            } else {
                Text(value)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 72)
        .frame(minHeight: 24)
    }
}

private struct PaywallFooterButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaywallFooterLabel(icon: icon, title: title)
        }
        .buttonStyle(.plain)
    }
}

private struct PaywallFooterLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30)

            Text(title)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
