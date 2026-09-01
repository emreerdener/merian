import Charts
import SwiftUI

struct SpeciesObservationChartContent: View {
    let selectedTab: SpeciesObservationChartTab
    let localStats: SpeciesObservationLocalStats
    let publicStats: SpeciesObservationStatsEntry?
    let seasonalityModel: SpeciesSeasonalityHeatmapModel
    let emptyDetail: String

    var body: some View {
        switch selectedTab {
        case .seasonality:
            seasonalityHeatmap
        case .history:
            historyChart
        case .lifeStage:
            monthChart
        }
    }

    private var seasonalityHeatmap: some View {
        Group {
            if seasonalityModel.hasContent {
                SpeciesObservationSeasonalityHeatmapView(
                    model: seasonalityModel
                )
            } else {
                emptyChartState(title: "No seasonal observations yet")
            }
        }
    }

    private var monthChart: some View {
        let points = SpeciesObservationChartPresentation
            .normalizedCategoryPoints(
                localSeries: localStats.lifeStage,
                publicSeries: publicStats?.lifeStage ?? []
            )

        return Group {
            if points.contains(where: \.hasObservations) {
                Chart(points) { point in
                    LineMark(
                        x: .value("Month", point.month),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        by: .value("Series", point.seriesName)
                    )

                    PointMark(
                        x: .value("Month", point.month),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .foregroundStyle(
                        by: .value("Series", point.seriesName)
                    )
                    .symbolSize(point.hasObservations ? 34 : 10)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis { percentageAxisMarks }
                .chartXAxis {
                    AxisMarks(values: Array(1...12)) { value in
                        AxisValueLabel {
                            if let month = value.as(Int.self) {
                                Text(
                                    SpeciesObservationChartPresentation
                                        .monthAbbreviation(for: month)
                                )
                            }
                        }
                    }
                }
            } else {
                emptyChartState(title: "No life-stage observations yet")
            }
        }
    }

    private var historyChart: some View {
        let points = SpeciesObservationChartPresentation
            .normalizedHistoryPoints([
                ("Local", localStats.history),
                ("Public", publicStats?.history ?? [])
            ])

        return Group {
            if points.contains(where: \.hasObservations) {
                Chart(points) { point in
                    LineMark(
                        x: .value("Month", point.date),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        by: .value("Series", point.seriesName)
                    )

                    PointMark(
                        x: .value("Month", point.date),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .foregroundStyle(
                        by: .value("Series", point.seriesName)
                    )
                    .symbolSize(point.hasObservations ? 28 : 8)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis { percentageAxisMarks }
            } else {
                emptyChartState(title: "No observation history yet")
            }
        }
    }

    @AxisContentBuilder
    private var percentageAxisMarks: some AxisContent {
        AxisMarks(values: [0.0, 0.5, 1.0]) { value in
            AxisGridLine()
            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text("\(Int(raw * 100))%")
                }
            }
        }
    }

    private func emptyChartState(title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(emptyDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}
