import RevenueCat
import SwiftUI

struct PaywallHeroSlide: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let subtitle: String
    let glowColor: Color
}

struct PaywallFeatureComparison: Identifiable {
    let id = UUID()
    let title: String
    let freeValue: String
    let proValue: String
}

enum ProPlanValueProps {
    static let activePlanSummary = "You have unlimited field scans, Pro AI vision, video scans, AI chat, multi-capture, Apple Watch logging, and expedition mode unlocked."
    static let upgradePlanSummary = "You have 1 free scan daily. Upgrade for unlimited field scans, Pro AI vision, video scans, AI chat, multi-capture, Apple Watch logging, and expedition mode."

    static let featuredSlides = [
        PaywallHeroSlide(
            imageName: "luna-moth",
            title: "Unlimited field scans",
            subtitle: "Keep identifying without daily scan limits.",
            glowColor: .mint
        ),
        PaywallHeroSlide(
            imageName: "hawk",
            title: "Pro AI vision",
            subtitle: "Use Merian's most capable model for deeper analysis.",
            glowColor: .orange
        ),
        PaywallHeroSlide(
            imageName: "blue-bird",
            title: "Listen, compare, record",
            subtitle: "Unlock multi-capture context, expedition modes, and richer insight cards.",
            glowColor: .cyan
        )
    ]

    static let comparisons = [
        PaywallFeatureComparison(title: "Daily scans", freeValue: "1", proValue: "Unlimited"),
        PaywallFeatureComparison(title: "AI model", freeValue: "Flash", proValue: "Pro"),
        PaywallFeatureComparison(title: "Video scans", freeValue: "-", proValue: "Included"),
        PaywallFeatureComparison(title: "AI chat", freeValue: "-", proValue: "Included"),
        PaywallFeatureComparison(title: "Multi-capture", freeValue: "-", proValue: "Included"),
        PaywallFeatureComparison(title: "Apple Watch logging", freeValue: "-", proValue: "Included"),
        PaywallFeatureComparison(title: "Group events", freeValue: "Join only", proValue: "Host"),
        PaywallFeatureComparison(title: "Expedition mode", freeValue: "-", proValue: "Included")
    ]
}

private struct PaywallReview: Identifiable {
    let id = UUID()
    let title: String
    let rating: Int
    let body: String
    let author: String
}

private let paywallReviews = [
    PaywallReview(
        title: "Essential field tool",
        rating: 5,
        body: "Merian Pro has completely transformed my weekend hikes. The expedition mode saves so much battery, and the Pro AI offline capabilities are insanely accurate.",
        author: "ForestPathfinder"
    ),
    PaywallReview(
        title: "Stunning UI & details",
        rating: 5,
        body: "The depth of local ecological information inside the Pro insight cards is exceptional. Highly recommend it to anyone wanting to learn more about the outdoors.",
        author: "EcoExplorer"
    ),
    PaywallReview(
        title: "Absolutely worth it",
        rating: 5,
        body: "Unlimited scans are a must! I take dozens of pictures of mosses and lichens during fieldwork and the app never misses a beat. Essential for my job.",
        author: "BioResearcher"
    )
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
        NavigationStack {
            GeometryReader { geometry in
                let availableHeight = geometry.size.height
                let isCompact = availableHeight < 620

                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: isCompact ? 20 : 30) {
                            heroCarousel(availableHeight: availableHeight, isCompact: isCompact)
                                .padding(.horizontal, -20)

                            planPicker(isCompact: isCompact)

                            comparisonSection

                            reviewsStack
                                .padding(.bottom, 8)

                            memberSupportedSection

                            paywallActionLinks
                                .padding(.bottom, 16)

                            if isCompact {
                                purchaseBar(isCompact: true)
                                    .padding(.bottom, 8)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .safeAreaInset(edge: .bottom) {
                        if !isCompact {
                            purchaseBar(isCompact: false)
                        }
                    }
                }
            }
            .navigationTitle("Merian Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .presentationDragIndicator(.hidden)
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

    private func heroCarousel(availableHeight: CGFloat, isCompact: Bool) -> some View {
        let carouselHeight = isCompact ? min(320, availableHeight * 0.45) : 388
        return TabView(selection: $selectedHeroIndex) {
            ForEach(Array(ProPlanValueProps.featuredSlides.enumerated()), id: \.element.id) { index, slide in
                PaywallHeroSlideView(slide: slide, isCompact: isCompact, availableHeight: availableHeight)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: carouselHeight)
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
                ForEach(ProPlanValueProps.featuredSlides.indices, id: \.self) { index in
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
    private func planPicker(isCompact: Bool) -> some View {
        if revenueCatManager.isFetchingOfferings && packages.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.accentColor)
                Text("Loading Pro plans...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 160 : 190)
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
            .frame(maxWidth: .infinity, minHeight: isCompact ? 160 : 190)
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
                                isSelected: package.identifier == selectedPackage?.identifier,
                                isCompact: isCompact
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

                ForEach(Array(ProPlanValueProps.comparisons.enumerated()), id: \.element.id) { index, comparison in
                    PaywallComparisonRow(comparison: comparison)

                    if index < ProPlanValueProps.comparisons.count - 1 {
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

            Image("heron")
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

    private var reviewsStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(paywallReviews.enumerated()), id: \.element.id) { index, review in
                PaywallReviewRowView(review: review)
                
                if index < paywallReviews.count - 1 {
                    Divider()
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func purchaseBar(isCompact: Bool) -> some View {
        if !packages.isEmpty {
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
            .padding(.horizontal, isCompact ? 8 : 28)
            .padding(.top, isCompact ? 8 : 14)
            .padding(.bottom, isCompact ? 8 : 12)
        }
    }

    private var paywallActionLinks: some View {
        HStack(spacing: 24) {
            if let termsUrl = URL(string: "https://merian.earth/terms") {
                Link("Terms", destination: termsUrl)
                    .foregroundStyle(.secondary)
            }
            
            if let privacyUrl = URL(string: "https://merian.earth/privacy") {
                Link("Privacy", destination: privacyUrl)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                Task { await tryRestore() }
            } label: {
                HStack(spacing: 4) {
                    Text("Restore")
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(.plain)
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

        if selectedPackage.isSevenDayPassPlan {
            return "\(selectedPackage.paywallDisplayPrice) for 7 days"
        }

        if selectedPackage.isAnnualPlan {
            return "\(selectedPackage.paywallDisplayPrice) per year. Cancel anytime."
        }

        let price = selectedPackage.paywallDisplayPrice
        switch selectedPackage.packageType {
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
            ?? packages.first(where: \.isAnnualPlan)
            ?? packages.first(where: { $0.packageType == .monthly })
            ?? packages.first
    }

    private func packageSortRank(_ package: Package) -> Int {
        if package.isSevenDayPassPlan { return 0 }
        if package.isAnnualPlan { return 1 }

        switch package.packageType {
        case .monthly: return 2
        case .lifetime: return 3
        default: return 4
        }
    }

    @MainActor
    private func autoAdvanceHeroCarousel() async {
        guard !heroCarouselAutoAdvanceDisabled, ProPlanValueProps.featuredSlides.count > 1 else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }

            guard !Task.isCancelled, !heroCarouselAutoAdvanceDisabled else { return }

            withAnimation(.easeInOut(duration: 0.35)) {
                selectedHeroIndex = (selectedHeroIndex + 1) % ProPlanValueProps.featuredSlides.count
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

private struct PaywallReviewRowView: View {
    let review: PaywallReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            HStack(spacing: 3) {
                ForEach(0..<review.rating, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            
            Text(review.body)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.primary.opacity(0.85))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
            
            Text(review.author)
                .font(.system(size: 13, weight: .medium).italic())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct PaywallHeroSlideView: View {
    let slide: PaywallHeroSlide
    let isCompact: Bool
    let availableHeight: CGFloat

    var body: some View {
        let imageHeight: CGFloat = isCompact ? min(130, availableHeight * 0.18) : 184
        let containerHeight: CGFloat = isCompact ? min(200, availableHeight * 0.26) : 276

        VStack(spacing: isCompact ? 8 : 16) {
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
                    .frame(width: 350, height: containerHeight)
                    .accessibilityHidden(true)

                Image(slide.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: imageHeight)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 10)
            }
            .frame(height: containerHeight)
            .frame(maxWidth: .infinity)

            VStack(spacing: isCompact ? 4 : 7) {
                Text(slide.title)
                    .font(.system(size: isCompact ? 22 : 29, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.86)

                Text(slide.subtitle)
                    .font(.system(size: isCompact ? 14 : 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.bottom, isCompact ? 12 : 26)
    }
}

private struct PaywallPlanCard: View {
    let package: Package
    let isSelected: Bool
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: isCompact ? 8 : 14) {
                HStack(alignment: .top) {
                    Text(badgeText)
                        .font(.system(size: isCompact ? 10 : 12, weight: .heavy))
                        .foregroundStyle(accent)
                        .padding(.horizontal, isCompact ? 10 : 12)
                        .padding(.vertical, isCompact ? 5 : 7)
                        .background(accent.opacity(0.14), in: Capsule())

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: isCompact ? 20 : 25, weight: .bold))
                        .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: isCompact ? 4 : 7) {
                    Text(planName)
                        .font(.system(size: isCompact ? 28 : 34, weight: .heavy))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(planDescription)
                        .font(.system(size: isCompact ? 15 : 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineSpacing(isCompact ? 2 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(package.paywallDisplayPrice)
                            .font(.system(size: isCompact ? 24 : 28, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(priceSuffix)
                            .font(.system(size: isCompact ? 15 : 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(renewalText)
                        .font(.system(size: isCompact ? 12 : 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
            }
            .padding(.top, isCompact ? 14 : 18)
            .padding(.horizontal, isCompact ? 16 : 20)
            .padding(.bottom, isCompact ? 16 : 22)
            .frame(width: isCompact ? 280 : 310, height: isCompact ? 210 : 252)
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
        default: return package.storeProduct.localizedTitle.replacingOccurrences(of: "Merian", with: "")
        }
    }

    private var planDescription: String {
        if package.isSevenDayPassPlan {
            return "Full Merian Pro access for 7 days."
        }
        if package.isAnnualPlan {
            return "The full Merian Pro experience for a year."
        }

        switch package.packageType {
        case .monthly: return "All Pro tools with month-to-month flexibility."
        case .weekly: return "A short pass for trips, classes, and field days."
        case .lifetime: return "Pay once and keep every Pro feature for life."
        default: return package.storeProduct.localizedDescription
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
        if package.isSevenDayPassPlan { return "One-time access. No subscription." }
        if package.isAnnualPlan { return "Plan auto-renews annually. Cancel anytime." }

        switch package.packageType {
        case .monthly: return "Plan auto-renews monthly. Cancel anytime."
        case .weekly: return "One week of Pro."
        case .lifetime: return "One-time purchase."
        default: return package.storeProduct.localizedDescription
        }
    }
}

private enum PaywallFixedPlanDisplay {
    static let sevenDayPassPrice = "$3.99"
    static let annualPrice = "$24.99"
    static let annualProductIdentifier = "pro_annual"
}

private extension Package {
    var isAnnualPlan: Bool {
        packageType == .annual
            || storeProduct.productIdentifier == PaywallFixedPlanDisplay.annualProductIdentifier
    }

    var isSevenDayPassPlan: Bool {
        if packageType == .weekly || storeProduct.productIdentifier == SevenDayPassAccessPolicy.productIdentifier {
            return true
        }

        let searchableText = [
            identifier,
            storeProduct.productIdentifier,
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

    var paywallDisplayPrice: String {
        if isSevenDayPassPlan { return PaywallFixedPlanDisplay.sevenDayPassPrice }
        if isAnnualPlan { return PaywallFixedPlanDisplay.annualPrice }
        return storeProduct.localizedPriceString
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
