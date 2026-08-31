import SwiftData
import SwiftUI

struct SpeciesObservationChartsCard: View {
    let speciesId: String?
    let scientificName: String

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SpeciesObservationStatsViewModel
    @State private var selectedTab: SpeciesObservationChartTab = .seasonality

    init(
        speciesId: String?,
        scientificName: String,
        dependencies: SpeciesObservationStatsDependencies = .live
    ) {
        self.speciesId = speciesId
        self.scientificName = scientificName
        _viewModel = State(
            initialValue: SpeciesObservationStatsViewModel(
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.hasAnyData {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Picker("Chart", selection: $selectedTab) {
                        ForEach(SpeciesObservationChartTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    SpeciesObservationChartContent(
                        selectedTab: selectedTab,
                        localStats: viewModel.localStats,
                        publicStats: viewModel.publicStats,
                        seasonalityModel: seasonalityHeatmapModel,
                        emptyDetail: emptyDetail
                    )
                    .frame(height: 230)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilitySummary)

                    if selectedTab != .seasonality ||
                        viewModel.publicErrorMessage != nil {
                        footer
                    }
                }
                .card()
            }
        }
        .task(id: loadKey) {
            await viewModel.load(
                speciesId: speciesId?.validStatsSpeciesId,
                scientificName: scientificName,
                modelContext: modelContext
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            InsightCardHeader(
                systemImage: "chart.xyaxis.line",
                title: "Observation patterns"
            )

            Spacer(minLength: 12)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if selectedTab != .seasonality {
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedTab != .seasonality,
               let rawCountLine {
                Text(rawCountLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedTab != .seasonality,
               let publicStats = viewModel.publicStats,
               publicStats.status == .partial || publicStats.status == .stale {
                Text(
                    publicStats.status == .stale
                        ? "Using cached public data."
                        : "Some public annotation buckets are still refreshing."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if viewModel.publicErrorMessage != nil {
                Text(
                    selectedTab == .seasonality
                        ? "Some observation data is unavailable; available months are still shown."
                        : "Public baseline unavailable; local observations are still shown."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var seasonalityHeatmapModel: SpeciesSeasonalityHeatmapModel {
        SpeciesSeasonalityHeatmapModel.make(
            localValues: viewModel.localStats.seasonality,
            localTotal: viewModel.localStats.totalObservations,
            publicValues: viewModel.publicStats?.seasonality,
            publicTotal: viewModel.publicStats?.totalObservations
        )
    }

    private var summaryLine: String {
        let local = "\(viewModel.localStats.totalObservations) local"
        let publicTotal = viewModel.publicStats?.totalObservations ?? 0
        let publicSummary = "\(publicTotal.formatted()) public"
        return "Relative scale keeps \(local) observations visible beside \(publicSummary)."
    }

    private var emptyDetail: String {
        switch selectedTab {
        case .seasonality:
            return "Observations will appear here as this species is recorded."
        case .history:
            return "Local logs will appear here as this species is recorded."
        case .lifeStage:
            return "Naturebook shows local life stages when the log includes them and public iNaturalist annotations when available."
        }
    }

    private var accessibilitySummary: String {
        if selectedTab == .seasonality {
            return [
                "Seasonality heatmap for \(scientificName).",
                seasonalityHeatmapModel.accessibilitySummary,
                rawCountLine
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }

        return [
            "\(selectedTab.title) chart for \(scientificName).",
            summaryLine,
            rawCountLine
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private var rawCountLine: String? {
        switch selectedTab {
        case .seasonality:
            return seasonalityHeatmapModel.detailLine
        case .history:
            return SpeciesObservationChartPresentation.joinedRawSummaries([
                SpeciesObservationChartPresentation.peakHistorySummary(
                    name: "Local",
                    values: viewModel.localStats.history
                ),
                SpeciesObservationChartPresentation.peakHistorySummary(
                    name: "Public",
                    values: viewModel.publicStats?.history ?? []
                )
            ])
        case .lifeStage:
            return SpeciesObservationChartPresentation.joinedRawSummaries([
                SpeciesObservationChartPresentation.topCategorySummary(
                    name: "Local",
                    series: viewModel.localStats.lifeStage
                ),
                SpeciesObservationChartPresentation.topCategorySummary(
                    name: "Public",
                    series: viewModel.publicStats?.lifeStage ?? []
                )
            ])
        }
    }

    private var loadKey: String {
        "\(speciesId ?? "name"):\(scientificName)"
    }
}

private extension String {
    var validStatsSpeciesId: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return trimmed
    }
}
