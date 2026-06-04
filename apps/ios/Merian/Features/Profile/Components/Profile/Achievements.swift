import SwiftData
import SwiftUI
import UIKit

// MARK: - Gamification Database Engine
extension ProfileDatabaseActor {
    func calculateAwards() -> [AwardPayload] {
        calculateAwardsProjection()
    }
}

// MARK: - Primary View
struct Achievements: View {
    @Environment(\.modelContext) private var modelContext

    let awards: [AwardPayload]
    var allowsDetailPresentation = true

    @State private var sortOption: AwardSortOption = .smartSort
    @State private var selectedAward: AwardPayload?

    private var sortedAwards: [AwardPayload] {
        switch sortOption {
        case .smartSort:
            return awards.sorted { a, b in
                func smartScore(for award: AwardPayload) -> Double {
                    if award.isCompleted {
                        if let date = award.lastInteractionDate, Date().timeIntervalSince(date) < 86400 * 7 {
                            return 3.0
                        }
                        return 1.0
                    }
                    if award.progressFraction > 0 {
                        return 2.0 + award.progressFraction
                    }
                    return 0.0
                }

                let scoreA = smartScore(for: a)
                let scoreB = smartScore(for: b)

                if abs(scoreA - scoreB) < 0.001 {
                    if let dateA = a.lastInteractionDate, let dateB = b.lastInteractionDate {
                        return dateA > dateB
                    }
                    if a.lastInteractionDate != nil { return true }
                    if b.lastInteractionDate != nil { return false }
                    return a.difficultyLevel < b.difficultyLevel
                }

                return scoreA > scoreB
            }
        case .completedFirst:
            return awards.sorted {
                if $0.isCompleted == $1.isCompleted { return $0.difficultyLevel < $1.difficultyLevel }
                return $0.isCompleted && !$1.isCompleted
            }
        case .uncompletedFirst:
            return awards.sorted {
                if $0.isCompleted == $1.isCompleted { return $0.difficultyLevel < $1.difficultyLevel }
                return !$0.isCompleted && $1.isCompleted
            }
        case .easiestFirst:
            return awards.sorted {
                if $0.difficultyLevel == $1.difficultyLevel { return $0.isCompleted && !$1.isCompleted }
                return $0.difficultyLevel < $1.difficultyLevel
            }
        case .hardestFirst:
            return awards.sorted {
                if $0.difficultyLevel == $1.difficultyLevel { return $0.isCompleted && !$1.isCompleted }
                return $0.difficultyLevel > $1.difficultyLevel
            }
        }
    }

    // MARK: - Achievements View
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Achievements Header
            HStack(alignment: .center) {
                Text("Achievements")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Picker(
                        "Sort achievements",
                        selection: Binding(
                            get: { sortOption },
                            set: { option in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    sortOption = option
                                }
                            }
                        )
                    ) {
                        ForEach(AwardSortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.iconName)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.75))

                        Text(sortOption.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .animation(.none, value: sortOption)
                .accessibilityLabel("Sorted by \(sortOption.rawValue)")
            }
            .padding(.top, 16)

            // Achievements List
            VStack(spacing: 12) {
                ForEach(sortedAwards) { award in
                    if allowsDetailPresentation {
                        Button {
                            selectedAward = award
                        } label: {
                            AchievementCard(award: award)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("AchievementCard_\(award.type.rawValue)")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(award.cardAccessibilityLabel)
                        .accessibilityHint(award.cardAccessibilityHint)
                    } else {
                        AchievementCard(award: award)
                            .accessibilityIdentifier("AchievementCard_\(award.type.rawValue)")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(award.cardAccessibilityLabel)
                            .accessibilityHint("Public achievement progress. Qualifying scans are private.")
                    }
                }
            }
        }
        .sheet(item: $selectedAward) { award in
            AchievementDetailSheet(award: award, modelContainer: modelContext.container)
        }
    }
}

private struct AchievementDetailSheet: View {
    let award: AwardPayload
    let modelContainer: ModelContainer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var detail: AchievementDetailPayload?
    @State private var isLoading = true
    @State private var selectedScanForInsight: ScanInsightRoute?

    private var resolvedAward: AwardPayload {
        detail?.award ?? award
    }

    private var contributions: [AchievementContribution] {
        detail?.contributions ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AchievementDetailHeader(award: resolvedAward)

                    if isLoading {
                        loadingState
                    } else if contributions.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(resolvedAward.qualifyingScansTitle)
                                .font(.headline)
                                .foregroundColor(.primary)

                            LazyVStack(spacing: 12) {
                                ForEach(contributions) { contribution in
                                    AchievementContributionRow(contribution: contribution) {
                                        openInsight(for: contribution)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(resolvedAward.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityIdentifier("AchievementDetailSheet_Close")
                }
            }
        }
        .accessibilityIdentifier("AchievementDetailSheet_\(award.type.rawValue)")
        .sheet(item: $selectedScanForInsight) { route in
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedScanForInsight != nil },
                    set: { if !$0 { selectedScanForInsight = nil } }
                ),
                initialScanId: route.scanId,
                inferenceEngine: inferenceEngine
            )
        }
        .task(id: award.id) {
            await loadDetail()
        }
        .onChange(of: selectedScanForInsight) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                Task {
                    await loadDetail(backgroundReload: true)
                }
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading qualifying scans...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var emptyState: some View {
        Text("No qualifying scans count toward this achievement yet.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }

    @MainActor
    private func loadDetail(backgroundReload: Bool = false) async {
        if !backgroundReload {
            isLoading = true
        }

        let actor = ProfileDatabaseActor(modelContainer: modelContainer)
        let resolvedDetail = await actor.calculateAchievementDetail(for: award.type)
        guard !Task.isCancelled else { return }

        detail = resolvedDetail
        
        if !backgroundReload {
            isLoading = false

            let telemetryAward = resolvedDetail?.award ?? award
            AppTelemetry.trackAchievementDetailOpened(
                type: telemetryAward.type.rawValue,
                state: telemetryAward.isCompleted ? "completed" : "in_progress"
            )

            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: telemetryAward.accessibilityProgressSummary
                )
            }
        }
    }

    @MainActor
    private func openInsight(for contribution: AchievementContribution) {
        guard let record = fetchScan(withID: contribution.scanID) else { return }

        AppTelemetry.trackAchievementContributionOpened(type: resolvedAward.type.rawValue)
        inferenceEngine.load(from: record)
        selectedScanForInsight = ScanInsightRoute(scanId: record.id)
    }

    @MainActor
    private func fetchScan(withID scanID: String) -> LocalScanRecord? {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanID }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

private struct AchievementDetailHeader: View {
    let award: AwardPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(award.descriptionText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(award.currentCount)/\(award.targetCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(award.progressStatusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(award.isCompleted ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    award.isCompleted
                                        ? Color.green.opacity(0.16)
                                        : Color(uiColor: .tertiarySystemFill)
                                )
                        )
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .systemGray6))
                            .frame(height: 8)

                        Capsule()
                            .fill(award.isCompleted ? Color.green.opacity(0.85) : award.tintInfo.color.opacity(0.85))
                            .frame(width: max(0, geo.size.width * award.progressFraction), height: 8)
                    }
                }
                .frame(height: 8)

                Text(award.detailProgressDescription)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(award.accessibilityProgressSummary)
    }
}

private struct AchievementContributionRow: View {
    let contribution: AchievementContribution
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ScanThumbnail(
                    imagePath: contribution.imagePath,
                    fallbackImageUrl: contribution.fallbackImageUrl,
                    audioPath: contribution.audioPath,
                    maxDimension: 240,
                    placeholderStyle: contribution.placeholderStyle
                )
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(contribution.commonName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Text(contribution.scientificName)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .italic()

                    Text(contribution.reasonText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )

                    Text(metadataText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("AchievementContribution_\(contribution.scanID)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this qualifying scan in the insight sheet.")
    }

    private var metadataText: String {
        var segments = [contribution.timestamp.formatted(date: .abbreviated, time: .shortened)]
        if let locationName = contribution.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locationName.isEmpty {
            segments.append(locationName)
        }
        return segments.joined(separator: " • ")
    }

    private var accessibilityLabel: String {
        var components = [contribution.commonName]

        if contribution.scientificName != contribution.commonName {
            components.append(contribution.scientificName)
        }

        components.append(contribution.reasonText)
        components.append(contribution.timestamp.formatted(date: .abbreviated, time: .shortened))

        if let locationName = contribution.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locationName.isEmpty {
            components.append(locationName)
        }

        return components.joined(separator: ". ")
    }
}
