import RevenueCat
import SwiftUI

struct PaywallView: View {
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = PaywallViewModel()
    @State private var selectedPackageIdentifier: String?
    @State private var selectedHeroIndex = 0
    @State private var heroCarouselAutoAdvanceDisabled = false

    private var packages: [Package] {
        (revenueCatManager.currentOfferings?.current?.availablePackages ?? [])
            .sorted { $0.paywallSortRank < $1.paywallSortRank }
    }

    private var selectedPackage: Package? {
        if let selectedPackageIdentifier,
           let package = packages.first(where: {
               $0.identifier == selectedPackageIdentifier
           }) {
            return package
        }

        return PaywallPackageSelectionPolicy.preferredPackage(from: packages)
    }

    private var isShowingOperationError: Binding<Bool> {
        Binding(
            get: { viewModel.operationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.operationErrorMessage = nil
                }
            }
        )
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
                            heroCarousel(
                                availableHeight: availableHeight,
                                isCompact: isCompact
                            )
                            .padding(.horizontal, -20)

                            planPicker(isCompact: isCompact)
                            comparisonSection

                            reviewsStack
                                .padding(.bottom, 8)

                            memberSupportedSection

                            paywallActionLinks
                                .padding(.bottom, 16)
                        }
                        .padding(.horizontal, 20)
                        .padding(
                            .bottom,
                            packages.isEmpty
                                ? 24
                                : purchaseBarScrollClearance(
                                    isCompact: isCompact
                                )
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    purchaseBar(isCompact: isCompact)
                }
            }
            .navigationTitle(PublicBrand.proName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: dismiss.callAsFunction) {
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
                await viewModel.fetchOfferings()
            }
            selectDefaultPackageIfNeeded()
        }
        .onChange(of: packages.map(\.identifier)) { _, _ in
            selectDefaultPackageIfNeeded()
        }
        .alert(
            "Unable to Complete Purchase",
            isPresented: isShowingOperationError
        ) {
            Button("OK", role: .cancel) {
                viewModel.operationErrorMessage = nil
            }
        } message: {
            Text(
                viewModel.operationErrorMessage ?? "Please try again."
            )
        }
    }

    private func heroCarousel(
        availableHeight: CGFloat,
        isCompact: Bool
    ) -> some View {
        let carouselHeight = isCompact
            ? min(340, availableHeight * 0.5)
            : 420

        return TabView(selection: $selectedHeroIndex) {
            ForEach(
                Array(ProPlanValueProps.featuredSlides.enumerated()),
                id: \.element.id
            ) { index, slide in
                PaywallHeroSlideView(
                    slide: slide,
                    isCompact: isCompact,
                    availableHeight: availableHeight
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: carouselHeight)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in
                    heroCarouselAutoAdvanceDisabled = true
                }
        )
        .task(id: heroCarouselAutoAdvanceDisabled) {
            await autoAdvanceHeroCarousel()
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 7) {
                ForEach(
                    ProPlanValueProps.featuredSlides.indices,
                    id: \.self
                ) { index in
                    Capsule()
                        .fill(
                            index == selectedHeroIndex
                                ? Color.primary
                                : Color.secondary.opacity(0.26)
                        )
                        .frame(
                            width: index == selectedHeroIndex ? 20 : 7,
                            height: 7
                        )
                        .animation(
                            .snappy(duration: 0.2),
                            value: selectedHeroIndex
                        )
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
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(planPickerBorder)
        } else if packages.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "leaf.circle")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.mint)

                Text("Plans are unavailable right now.")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(
                    "Please check your connection or try restoring an existing purchase."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 160 : 190)
            .padding(.horizontal, 22)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(planPickerBorder)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(packages) { package in
                            PaywallPlanCard(
                                package: package,
                                isSelected: package.identifier ==
                                    selectedPackage?.identifier,
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

    private var planPickerBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(
                Color(uiColor: .separator).opacity(0.35),
                lineWidth: 1
            )
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

                ForEach(
                    Array(ProPlanValueProps.comparisons.enumerated()),
                    id: \.element.id
                ) { index, comparison in
                    PaywallComparisonRow(comparison: comparison)

                    if index < ProPlanValueProps.comparisons.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        Color(uiColor: .separator).opacity(0.22),
                        lineWidth: 1
                    )
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

            Text(
                "Pro keeps Naturebook moving: better models, richer ecological context, and field tools that work where discovery happens."
            )
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
            ForEach(
                Array(ProPlanValueProps.reviews.enumerated()),
                id: \.element.id
            ) { index, review in
                PaywallReviewRowView(review: review)

                if index < ProPlanValueProps.reviews.count - 1 {
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
                    if viewModel.isPurchasing {
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
                            ? [
                                Color.secondary.opacity(0.26),
                                Color.secondary.opacity(0.16)
                            ]
                            : [
                                Color(red: 0.10, green: 0.62, blue: 0.74),
                                Color(red: 0.13, green: 0.78, blue: 0.54)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            Color.primary.opacity(
                                selectedPackage == nil ? 0.08 : 0.18
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.34), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(
                selectedPackage == nil ||
                    viewModel.isPurchasing ||
                    viewModel.isRestoring ||
                    !revenueCatManager.isPurchaseIdentityReady
            )
            .padding(.horizontal, isCompact ? 8 : 28)
            .padding(.top, isCompact ? 8 : 14)
            .padding(.bottom, isCompact ? 8 : 12)
        }
    }

    private func purchaseBarScrollClearance(isCompact: Bool) -> CGFloat {
        isCompact ? 104 : 118
    }

    private var paywallActionLinks: some View {
        HStack(spacing: 24) {
            Link("Terms", destination: PublicBrand.websiteURL(path: "terms"))
                .foregroundStyle(.secondary)

            Link(
                "Privacy",
                destination: PublicBrand.websiteURL(path: "privacy")
            )
            .foregroundStyle(.secondary)

            Button {
                Task { await restorePurchases() }
            } label: {
                HStack(spacing: 4) {
                    Text("Restore")
                    if viewModel.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .disabled(
                !revenueCatManager.isPurchaseIdentityReady ||
                    viewModel.isRestoring ||
                    viewModel.isPurchasing
            )
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
        default: return "Start Naturebook Pro"
        }
    }

    private var purchaseButtonSubtitle: String {
        guard let selectedPackage else {
            return "Check back soon or restore purchases"
        }

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
        selectedPackageIdentifier = PaywallPackageSelectionPolicy
            .preferredPackage(from: packages)?
            .identifier
    }

    @MainActor
    private func autoAdvanceHeroCarousel() async {
        guard !heroCarouselAutoAdvanceDisabled,
              ProPlanValueProps.featuredSlides.count > 1 else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  !heroCarouselAutoAdvanceDisabled else { return }

            withAnimation(.easeInOut(duration: 0.35)) {
                selectedHeroIndex =
                    (selectedHeroIndex + 1) %
                    ProPlanValueProps.featuredSlides.count
            }
        }
    }

    private func restorePurchases() async {
        if await viewModel.restorePurchases() {
            dismiss()
        }
    }

    private func purchaseSelectedPackage() async {
        guard let selectedPackage else { return }
        if await viewModel.purchase(selectedPackage) {
            dismiss()
        }
    }
}
