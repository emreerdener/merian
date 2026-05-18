import Charts
import SwiftData
import SwiftUI

struct SpeciesObservationChartsCard: View {
    let speciesId: String?
    let scientificName: String

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SpeciesObservationStatsViewModel()
    @State private var selectedTab: SpeciesObservationChartTab = .seasonality

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                InsightCardHeader(systemImage: "chart.xyaxis.line", title: "Observation patterns")

                Spacer(minLength: 12)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Picker("Chart", selection: $selectedTab) {
                ForEach(SpeciesObservationChartTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            chartContent
                .frame(height: 230)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilitySummary)

            footer
        }
        .card()
        .task(id: loadKey) {
            await viewModel.load(
                speciesId: speciesId?.validStatsSpeciesId,
                scientificName: scientificName,
                modelContext: modelContext
            )
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        switch selectedTab {
        case .seasonality:
            monthChart(
                points: normalizedMonthPoints([
                    ("Local", viewModel.localStats.seasonality),
                    ("Public", viewModel.publicStats?.seasonality ?? [])
                ]),
                emptyTitle: "No seasonal observations yet"
            )
        case .history:
            historyChart(
                points: normalizedHistoryPoints([
                    ("Local", viewModel.localStats.history),
                    ("Public", viewModel.publicStats?.history ?? [])
                ]),
                emptyTitle: "No observation history yet"
            )
        case .lifeStage:
            monthChart(
                points: normalizedCategoryPoints(
                    localSeries: viewModel.localStats.lifeStage,
                    publicSeries: viewModel.publicStats?.lifeStage ?? []
                ),
                emptyTitle: "No life-stage observations yet"
            )
        case .sex:
            monthChart(
                points: normalizedCategoryPoints(
                    localSeries: [],
                    publicSeries: viewModel.publicStats?.sex ?? []
                ),
                emptyTitle: "No public sex annotations yet"
            )
        }
    }

    private func monthChart(points: [SpeciesObservationMonthChartPoint], emptyTitle: String) -> some View {
        Group {
            if points.contains(where: \.hasObservations) {
                Chart(points) { point in
                    LineMark(
                        x: .value("Month", point.month),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("Series", point.seriesName))

                    PointMark(
                        x: .value("Month", point.month),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .foregroundStyle(by: .value("Series", point.seriesName))
                    .symbolSize(point.hasObservations ? 34 : 10)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0.0, 0.5, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text("\(Int(raw * 100))%")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: Array(1...12)) { value in
                        AxisValueLabel {
                            if let month = value.as(Int.self) {
                                Text(Self.monthAbbreviation(for: month))
                            }
                        }
                    }
                }
            } else {
                emptyChartState(title: emptyTitle)
            }
        }
    }

    private func historyChart(points: [SpeciesObservationHistoryChartPoint], emptyTitle: String) -> some View {
        Group {
            if points.contains(where: \.hasObservations) {
                Chart(points) { point in
                    LineMark(
                        x: .value("Month", point.date),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("Series", point.seriesName))

                    PointMark(
                        x: .value("Month", point.date),
                        y: .value("Relative count", point.normalizedCount)
                    )
                    .foregroundStyle(by: .value("Series", point.seriesName))
                    .symbolSize(point.hasObservations ? 28 : 8)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0.0, 0.5, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text("\(Int(raw * 100))%")
                            }
                        }
                    }
                }
            } else {
                emptyChartState(title: emptyTitle)
            }
        }
    }

    private func emptyChartState(title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: selectedTab == .sex ? "person.2.slash" : "chart.line.uptrend.xyaxis")
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let rawCountLine {
                Text(rawCountLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let publicStats = viewModel.publicStats,
               publicStats.status == .partial || publicStats.status == .stale {
                Text(publicStats.status == .stale ? "Using cached public data." : "Some public annotation buckets are still refreshing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if viewModel.publicErrorMessage != nil {
                Text("Public baseline unavailable; local observations are still shown.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryLine: String {
        let local = "\(viewModel.localStats.totalObservations) local"
        let publicTotal = viewModel.publicStats?.totalObservations ?? 0
        let publicSummary = "\(publicTotal.formatted()) public"
        return "Relative scale keeps \(local) observations visible beside \(publicSummary)."
    }

    private var emptyDetail: String {
        switch selectedTab {
        case .seasonality, .history:
            return "Local logs will appear here as this species is recorded."
        case .lifeStage:
            return "Merian shows local life stages when the log includes them and public iNaturalist annotations when available."
        case .sex:
            return "Sex is external-only in this version because Merian does not capture sex locally."
        }
    }

    private var accessibilitySummary: String {
        [
            "\(selectedTab.title) chart for \(scientificName).",
            summaryLine,
            rawCountLine
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private var loadKey: String {
        "\(speciesId ?? "name"):\(scientificName)"
    }

    private func normalizedMonthPoints(
        _ series: [(String, [SpeciesObservationMonthCount])]
    ) -> [SpeciesObservationMonthChartPoint] {
        series.flatMap { name, values in
            guard !values.isEmpty else { return [SpeciesObservationMonthChartPoint]() }
            let maxCount = max(values.map(\.count).max() ?? 0, 1)
            return values.map { value in
                SpeciesObservationMonthChartPoint(
                    seriesName: name,
                    month: value.month,
                    count: value.count,
                    normalizedCount: Double(value.count) / Double(maxCount)
                )
            }
        }
    }

    private func normalizedCategoryPoints(
        localSeries: [SpeciesObservationCategorySeries],
        publicSeries: [SpeciesObservationCategorySeries]
    ) -> [SpeciesObservationMonthChartPoint] {
        let local = localSeries.map { ("Local \($0.label)", $0.values) }
        let publicValues = publicSeries.map { ("Public \($0.label)", $0.values) }
        return normalizedMonthPoints(local + publicValues)
    }

    private func normalizedHistoryPoints(
        _ series: [(String, [SpeciesObservationHistoryCount])]
    ) -> [SpeciesObservationHistoryChartPoint] {
        series.flatMap { name, values in
            guard !values.isEmpty else { return [SpeciesObservationHistoryChartPoint]() }
            let maxCount = max(values.map(\.count).max() ?? 0, 1)
            return values.map { value in
                SpeciesObservationHistoryChartPoint(
                    seriesName: name,
                    date: value.date,
                    count: value.count,
                    normalizedCount: Double(value.count) / Double(maxCount)
                )
            }
        }
    }

    private var rawCountLine: String? {
        switch selectedTab {
        case .seasonality:
            return joinedRawSummaries([
                peakMonthSummary(name: "Local", values: viewModel.localStats.seasonality),
                peakMonthSummary(name: "Public", values: viewModel.publicStats?.seasonality ?? [])
            ])
        case .history:
            return joinedRawSummaries([
                peakHistorySummary(name: "Local", values: viewModel.localStats.history),
                peakHistorySummary(name: "Public", values: viewModel.publicStats?.history ?? [])
            ])
        case .lifeStage:
            return joinedRawSummaries([
                topCategorySummary(name: "Local", series: viewModel.localStats.lifeStage),
                topCategorySummary(name: "Public", series: viewModel.publicStats?.lifeStage ?? [])
            ])
        case .sex:
            return topCategorySummary(name: "Public", series: viewModel.publicStats?.sex ?? [])
        }
    }

    private func peakMonthSummary(
        name: String,
        values: [SpeciesObservationMonthCount]
    ) -> String? {
        guard let peak = values.max(by: { $0.count < $1.count }),
              peak.hasObservations else {
            return nil
        }
        return "\(name) peak \(Self.monthAbbreviation(for: peak.month)): \(peak.count.formatted())"
    }

    private func peakHistorySummary(
        name: String,
        values: [SpeciesObservationHistoryCount]
    ) -> String? {
        guard let peak = values.max(by: { $0.count < $1.count }),
              peak.hasObservations else {
            return nil
        }
        return "\(name) peak \(Self.monthAbbreviation(for: peak.month)) \(peak.year): \(peak.count.formatted())"
    }

    private func topCategorySummary(
        name: String,
        series: [SpeciesObservationCategorySeries]
    ) -> String? {
        let totals = series.map { item in
            (label: item.label, total: item.values.reduce(0) { $0 + $1.count })
        }
        guard let top = totals.max(by: { $0.total < $1.total }),
              top.total.signum() == 1 else {
            return nil
        }
        return "\(name) top \(top.label.lowercased()): \(top.total.formatted())"
    }

    private func joinedRawSummaries(_ summaries: [String?]) -> String? {
        let resolved = summaries.compactMap { $0 }
        return resolved.isEmpty ? nil : resolved.joined(separator: " · ")
    }

    private static func monthAbbreviation(for month: Int) -> String {
        guard month >= 1 && month <= 12 else { return "" }
        return Calendar.current.shortMonthSymbols[month - 1]
    }
}

private enum SpeciesObservationChartTab: String, CaseIterable, Identifiable {
    case seasonality
    case history
    case lifeStage
    case sex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seasonality:
            return "Seasonality"
        case .history:
            return "History"
        case .lifeStage:
            return "Life Stage"
        case .sex:
            return "Sex"
        }
    }
}

private struct SpeciesObservationMonthChartPoint: Identifiable {
    let seriesName: String
    let month: Int
    let count: Int
    let normalizedCount: Double

    var id: String { "\(seriesName)-\(month)" }
    var hasObservations: Bool { count.signum() == 1 }
}

private struct SpeciesObservationHistoryChartPoint: Identifiable {
    let seriesName: String
    let date: Date
    let count: Int
    let normalizedCount: Double

    var id: String { "\(seriesName)-\(date.timeIntervalSince1970)" }
    var hasObservations: Bool { count.signum() == 1 }
}

private extension String {
    var validStatsSpeciesId: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return trimmed
    }
}
