import SwiftData
import SwiftUI

struct ActiveFieldTripsProfilePreview: View {
    let onOpenTemplate: (String) -> Void
    let onOpenCompletedScan: (String) -> Void
    let onViewAll: () -> Void
    let onEarnedPatchesChange: ([EarnedFieldTripPatch]) -> Void
    let onEarnedPatchesLoadingChange: (Bool) -> Void

    @Environment(SupabaseManager.self) private var supabase
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var viewModel: ActiveFieldTripsProfileViewModel

    init(
        onOpenTemplate: @escaping (String) -> Void,
        onOpenCompletedScan: @escaping (String) -> Void,
        onViewAll: @escaping () -> Void,
        onEarnedPatchesChange: @escaping ([EarnedFieldTripPatch]) -> Void,
        onEarnedPatchesLoadingChange: @escaping (Bool) -> Void
    ) {
        self.onOpenTemplate = onOpenTemplate
        self.onOpenCompletedScan = onOpenCompletedScan
        self.onViewAll = onViewAll
        self.onEarnedPatchesChange = onEarnedPatchesChange
        self.onEarnedPatchesLoadingChange = onEarnedPatchesLoadingChange
        _viewModel = State(
            initialValue: ActiveFieldTripsProfileViewModel(
                dependencies: .live(
                    earnedPatchesDidChange: onEarnedPatchesChange,
                    loadingDidChange: onEarnedPatchesLoadingChange
                )
            )
        )
    }

    private var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }

    private var localScansById: [String: LocalScanRecord] {
        localScans.reduce(into: [:]) { scans, scan in
            scans[scan.id] = scan
        }
    }

    var body: some View {
        Group {
            if !viewModel.items.isEmpty {
                content
            } else if viewModel.isLoading && !viewModel.hasLoaded {
                ActiveFieldTripsProfileSkeleton()
            }
        }
        .task(id: currentUserId) {
            await viewModel.load(isAuthenticated: currentUserId != nil)
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            switch event {
            case .fieldTripProgressInvalidated:
                Task { await viewModel.load(isAuthenticated: currentUserId != nil) }
            case .captureGoalContextInvalidated(let source) where source == .fieldTrip:
                Task { await viewModel.load(isAuthenticated: currentUserId != nil) }
            default:
                break
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ActiveFieldTripProfilePresentation.previewItems(from: viewModel.items)) { item in
                CurrentUserActiveFieldTripProfileCard(
                    item: item,
                    localScansById: localScansById,
                    onOpenTemplate: {
                        HapticManager.shared.triggerSelectionPulse()
                        onOpenTemplate(item.template.templateId)
                    },
                    onOpenCompletedScan: onOpenCompletedScan
                )
            }

            if ActiveFieldTripProfilePresentation.shouldShowViewAll(for: viewModel.items) {
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onViewAll()
                } label: {
                    HStack(spacing: 4) {
                        Text("View all field trips")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Field trips in Explore.")
            }
        }
    }

}

private struct CurrentUserActiveFieldTripProfileCard: View {
    let item: ActiveFieldTripProfileItem
    let localScansById: [String: LocalScanRecord]
    let onOpenTemplate: () -> Void
    let onOpenCompletedScan: (String) -> Void

    private var patchImageName: String? {
        FieldTripLevelArtwork.imageName(
            templateSlug: item.template.slug,
            levelNumber: item.currentLevelNumber
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpenTemplate) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FieldTripTemplatePresentation.title(item.template.title, slug: item.template.slug))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("Level \(item.currentLevelNumber)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    FieldTripActiveProfilePatch(imageName: patchImageName)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(FieldTripTemplatePresentation.title(item.template.title, slug: item.template.slug)), Level \(item.currentLevelNumber)"
            )
            .accessibilityValue(
                "\(item.completedCount) of \(item.targetCount) goals complete"
            )
            .accessibilityHint("Opens this Field trip")

            FieldTripScanPreviewStrip(
                targetCount: item.targetCount,
                templateSlug: item.template.slug,
                items: item.currentLevelItems,
                localScansById: localScansById,
                onOpenTemplate: onOpenTemplate,
                onOpenCompletedScan: onOpenCompletedScan,
                presentationMode: .responsiveCatalog
            )
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
    }
}

struct ActiveFieldTripsProfileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<ActiveFieldTripProfilePresentation.previewLimit, id: \.self) { _ in
                ActiveFieldTripProfileCardSkeleton()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ActiveFieldTripProfileCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(maxWidth: 176)
                        .frame(height: 24)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 64, height: 13)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Circle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 64, height: 64)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .redacted(reason: .placeholder)
    }
}
