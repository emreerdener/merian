import SwiftData
import SwiftUI

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
    @State private var sortOption: AwardSortOption = .smartSort
    @State private var selectedAward: AwardPayload?
    
    private var sortedAwards: [AwardPayload] {
        switch sortOption {
        case .smartSort:
            return awards.sorted { a, b in
                // Heuristic priority scoring:
                // >= 3.0: Freshly Completed (Within last 7 days)
                // 2.01 - 2.99: In Progress (Mathematically scales by closeness to completion)
                // 1.0: Legacy Completed (Older than 7 days)
                // 0.0: Conceptually empty (0%)
                func smartScore(for award: AwardPayload) -> Double {
                    if award.isCompleted {
                        if let date = award.lastInteractionDate, Date().timeIntervalSince(date) < 86400 * 7 {
                            return 3.0 // Hero status! Recently accomplished!
                        }
                        return 1.0 // Sink legacy accomplishments below active goals
                    }
                    if award.progressFraction > 0 {
                        return 2.0 + award.progressFraction // Organical float "close to being done" (e.g. 2.9) to the top of the In-Progress pile!
                    }
                    return 0.0 // Empty goals sink completely to the bottom
                }
                
                let scoreA = smartScore(for: a)
                let scoreB = smartScore(for: b)
                
                // If mathematically tied across the exact same heuristic tier boundaries...
                if abs(scoreA - scoreB) < 0.001 {
                    // Tie-breaker 1: Explicitly float the most recently interacted award logically!
                    if let dateA = a.lastInteractionDate, let dateB = b.lastInteractionDate {
                        return dateA > dateB
                    }
                    if a.lastInteractionDate != nil { return true }
                    if b.lastInteractionDate != nil { return false }
                    
                    // Tie-breaker 2: Fallback to difficulty geometry mapping (Green -> Amber -> Crimson)
                    return a.difficultyLevel < b.difficultyLevel
                }
                // Primary evaluator: float highest priority scores dynamically!
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Achievements")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Menu {
                    ForEach(AwardSortOption.allCases) { option in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                sortOption = option
                            }
                        }) {
                            Label(option.rawValue, systemImage: option.iconName)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial) // Liquid Glass frost
                        }
                        .overlay {
                            Circle()
                                // Inner specular glow replicating premium iOS reflections
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                }
            }
            
            VStack(spacing: 12) {
                ForEach(sortedAwards) { award in
                    Button {
                        selectedAward = award
                    } label: {
                        AchievementCard(award: award)
                    }
                    .buttonStyle(.plain)
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

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var detail: AchievementDetailPayload?
    @State private var scansByID: [String: LocalScanRecord] = [:]
    @State private var isLoading = true
    @State private var selectedScanForInsight: LocalScanRecord?

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
                    } else if contributions.isEmpty {
                        Text("No scans count toward this achievement yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Associated scans")
                                .font(.headline)
                                .foregroundColor(.primary)

                            LazyVStack(spacing: 12) {
                                ForEach(contributions) { contribution in
                                    AchievementContributionRow(
                                        contribution: contribution,
                                        record: scansByID[contribution.id]
                                    ) { record in
                                        inferenceEngine.load(from: record)
                                        selectedScanForInsight = record
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
        }
        .sheet(item: $selectedScanForInsight) { _ in
            InsightSheetView(isPresented: Binding(
                get: { selectedScanForInsight != nil },
                set: { if !$0 { selectedScanForInsight = nil } }
            ), inferenceEngine: inferenceEngine)
        }
        .task(id: award.id) {
            await loadDetail()
        }
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        let actor = ProfileDatabaseActor(modelContainer: modelContainer)
        let resolvedDetail = await actor.calculateAchievementDetail(for: award.type)
        guard !Task.isCancelled else { return }

        detail = resolvedDetail
        scansByID = fetchScansLookup(for: resolvedDetail?.contributions ?? [])
        isLoading = false
    }

    private func fetchScansLookup(
        for contributions: [AchievementContribution]
    ) -> [String: LocalScanRecord] {
        let scanIDs = contributions.map(\.id)
        guard !scanIDs.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { scanIDs.contains($0.id) }
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
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

                    Text(award.isCompleted ? "Completed" : "In progress")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(award.isCompleted ? Color(red: 0.25, green: 0.75, blue: 0.35) : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    award.isCompleted
                                        ? Color(red: 0.25, green: 0.75, blue: 0.35).opacity(0.14)
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
                            .fill(Color(red: 0.25, green: 0.75, blue: 0.35).opacity(0.85))
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
    }
}

private struct AchievementContributionRow: View {
    let contribution: AchievementContribution
    let record: LocalScanRecord?
    let onTap: (LocalScanRecord) -> Void

    var body: some View {
        Group {
            if let record {
                Button {
                    onTap(record)
                } label: {
                    rowContent(record: record)
                }
                .buttonStyle(.plain)
            } else {
                rowContent(record: nil)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private func rowContent(record: LocalScanRecord?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let record {
                ScanThumbnail(record: record, maxDimension: 240)
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 68, height: 68)
                    .overlay(
                        Image(systemName: "leaf")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(record?.commonName ?? contribution.scientificName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Text(record?.scientificName ?? contribution.scientificName)
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

                Text(contribution.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension AwardPayload {
    var detailProgressDescription: String {
        switch type.lowercased() {
        case "first_scan":
            return "Your first successful scan unlocks this achievement."
        default:
            return "Each unique qualifying species contributes once toward this achievement."
        }
    }
}
