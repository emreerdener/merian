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
            HStack(alignment: .center) {
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

            if selectedTab != .seasonality || viewModel.publicErrorMessage != nil {
                footer
            }
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
            seasonalityHeatmap(
                model: seasonalityHeatmapModel,
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

    private func seasonalityHeatmap(
        model: SpeciesSeasonalityHeatmapModel,
        emptyTitle: String
    ) -> some View {
        Group {
            if model.hasContent {
                SpeciesObservationSeasonalityHeatmapView(model: model)
            } else {
                emptyChartState(title: emptyTitle)
            }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                Text(selectedTab == .seasonality
                    ? "Some observation data is unavailable; available months are still shown."
                    : "Public baseline unavailable; local observations are still shown.")
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
        case .seasonality:
            return "Observations will appear here as this species is recorded."
        case .history:
            return "Local logs will appear here as this species is recorded."
        case .lifeStage:
            return "Merian shows local life stages when the log includes them and public iNaturalist annotations when available."
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
            return seasonalityHeatmapModel.detailLine
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
        }
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

private struct SpeciesObservationSeasonalityHeatmapView: View {
    let model: SpeciesSeasonalityHeatmapModel

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            if model.seasonalityUnavailable && !model.hasObservations {
                unavailableRow
            } else {
                monthGrid

                legendRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var legendRow: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(0..<4) { index in
                let intensity = Double(index) / 3.0
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(intensity: intensity))
                    .frame(width: 12, height: 12)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            ForEach(0..<3) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(0..<4) { colIndex in
                        let index = rowIndex * 4 + colIndex
                        if index < model.cells.count {
                            let cell = model.cells[index]
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(color(intensity: cell.displayIntensity))
                                .overlay {
                                    ZStack {
                                        if cell.hasObservations {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .strokeBorder(color(intensity: 1), lineWidth: 1)
                                                .opacity(0.28)
                                        }

                                        Text(Self.monthAbbreviation(for: cell.month))
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                            .foregroundStyle(cell.displayIntensity >= 0.55 ? .white : .secondary)
                                            .padding(.horizontal, 4)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityLabel(
                                    "\(Self.monthAbbreviation(for: cell.month)) \(cell.count) observations"
                                )
                        }
                    }
                }
            }
        }
    }

    private var unavailableRow: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Text("Seasonality unavailable")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(intensity: Double) -> Color {
        guard intensity > 0 else {
            return Color.secondary.opacity(0.12)
        }

        return Color.green.opacity(0.18 + (0.82 * intensity))
    }

    private static func monthAbbreviation(for month: Int) -> String {
        guard month >= 1 && month <= 12 else { return "" }
        return Calendar.current.shortMonthSymbols[month - 1]
    }
}

struct SpeciesSeasonalityHeatmapModel: Equatable, Sendable {
    let cells: [SpeciesSeasonalityHeatmapCell]
    let total: Int
    let detailLine: String?
    let seasonalityUnavailable: Bool

    var totalLine: String? {
        guard total.signum() == 1 else { return nil }
        let label = Self.observationLabel(for: total)
        return seasonalityUnavailable ? "\(label) represented" : label
    }

    var hasObservations: Bool {
        cells.contains(where: \.hasObservations)
    }

    var hasContent: Bool {
        hasObservations || seasonalityUnavailable
    }

    var accessibilitySummary: String {
        if seasonalityUnavailable && !hasObservations {
            return "Seasonality unavailable."
        }

        guard let peak = cells.max(by: { $0.count < $1.count }),
              peak.hasObservations else {
            return "No seasonal observations."
        }

        return [
            "\(Self.observationLabel(for: total)) \(seasonalityUnavailable ? "represented;" : "total;")",
            "peak \(Self.monthAbbreviation(for: peak.month)) \(peak.count.formatted())."
        ]
        .joined(separator: " ")
    }

    static func make(
        localValues: [SpeciesObservationMonthCount],
        localTotal: Int,
        publicValues: [SpeciesObservationMonthCount]?,
        publicTotal: Int?
    ) -> SpeciesSeasonalityHeatmapModel {
        let normalizedLocal = normalizedMonthValues(localValues)
        let normalizedPublic = publicValues.map { normalizedMonthValues($0) }
        let publicTotal = publicTotal ?? 0
        let publicHasMonthlyCounts = normalizedPublic?.contains(where: \.hasObservations) == true
        let publicSeasonalityUnavailable = publicTotal > 0 && publicHasMonthlyCounts == false

        let combinedValues = combinedMonthValues(
            localValues: normalizedLocal,
            publicValues: publicSeasonalityUnavailable ? nil : normalizedPublic
        )
        let total = localTotal + (publicSeasonalityUnavailable ? 0 : publicTotal)
        let maxCount = max(combinedValues.map(\.count).max() ?? 0, 1)
        let rawIntensities = combinedValues.map { value in
            Double(value.count) / Double(maxCount)
        }
        let displayIntensities = smoothedDisplayIntensities(rawIntensities)
        let cells = combinedValues.enumerated().map { index, value in
            SpeciesSeasonalityHeatmapCell(
                month: value.month,
                count: value.count,
                intensity: rawIntensities[index],
                displayIntensity: displayIntensities[index]
            )
        }

        return SpeciesSeasonalityHeatmapModel(
            cells: cells,
            total: total,
            detailLine: Self.detailLine(for: cells),
            seasonalityUnavailable: publicSeasonalityUnavailable
        )
    }

    private static func normalizedMonthValues(
        _ values: [SpeciesObservationMonthCount]
    ) -> [SpeciesObservationMonthCount] {
        let countsByMonth = values.reduce(into: [Int: Int]()) { result, value in
            result[value.month, default: 0] += value.count
        }
        return (1...12).map { month in
            SpeciesObservationMonthCount(month: month, count: countsByMonth[month, default: 0])
        }
    }

    private static func combinedMonthValues(
        localValues: [SpeciesObservationMonthCount],
        publicValues: [SpeciesObservationMonthCount]?
    ) -> [SpeciesObservationMonthCount] {
        let publicCountsByMonth = Dictionary(
            uniqueKeysWithValues: (publicValues ?? []).map { ($0.month, $0.count) }
        )
        return localValues.map { value in
            SpeciesObservationMonthCount(
                month: value.month,
                count: value.count + publicCountsByMonth[value.month, default: 0]
            )
        }
    }

    private static func detailLine(for cells: [SpeciesSeasonalityHeatmapCell]) -> String? {
        guard let peak = cells.max(by: { $0.count < $1.count }),
              peak.hasObservations else {
            return nil
        }

        return "Peak \(Self.monthAbbreviation(for: peak.month)): \(Self.observationLabel(for: peak.count))"
    }

    private static func monthAbbreviation(for month: Int) -> String {
        guard month >= 1 && month <= 12 else { return "" }
        return Calendar.current.shortMonthSymbols[month - 1]
    }

    private static func smoothedDisplayIntensities(_ rawIntensities: [Double]) -> [Double] {
        guard rawIntensities.count == 12,
              rawIntensities.contains(where: { $0 > 0 }) else {
            return rawIntensities
        }

        return rawIntensities.indices.map { index in
            let neighborIntensity = rawIntensities.indices
                .map { observedIndex -> Double in
                    guard rawIntensities[observedIndex] > 0 else { return 0 }
                    let distance = cyclicDistance(from: index, to: observedIndex, count: rawIntensities.count)
                    return rawIntensities[observedIndex] * falloff(for: distance)
                }
                .max() ?? 0

            return max(rawIntensities[index], neighborIntensity)
        }
    }

    private static func cyclicDistance(from index: Int, to otherIndex: Int, count: Int) -> Int {
        let distance = abs(index - otherIndex)
        return min(distance, count - distance)
    }

    private static func falloff(for distance: Int) -> Double {
        switch distance {
        case 0:
            return 1
        case 1:
            return 0.42
        case 2:
            return 0.18
        default:
            return 0
        }
    }

    private static func observationLabel(for count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "observation" : "observations")"
    }
}

struct SpeciesSeasonalityHeatmapCell: Equatable, Identifiable, Sendable {
    let month: Int
    let count: Int
    let intensity: Double
    let displayIntensity: Double

    var id: Int { month }
    var hasObservations: Bool { count.signum() == 1 }
}

private enum SpeciesObservationChartTab: String, CaseIterable, Identifiable {
    case seasonality
    case history
    case lifeStage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seasonality:
            return "Seasonality"
        case .history:
            return "History"
        case .lifeStage:
            return "Life Stage"
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

#if DEBUG
#Preview("Seasonality - combined") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: [
                SpeciesObservationMonthCount(month: 4, count: 1),
                SpeciesObservationMonthCount(month: 5, count: 1)
            ],
            localTotal: 2,
            publicValues: [
                SpeciesObservationMonthCount(month: 4, count: 39),
                SpeciesObservationMonthCount(month: 5, count: 50)
            ],
            publicTotal: 89
        )
    )
    .padding()
}

#Preview("Seasonality - partial data") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: [
                SpeciesObservationMonthCount(month: 5, count: 1)
            ],
            localTotal: 1,
            publicValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            publicTotal: 89
        )
    )
    .padding()
}

#Preview("Seasonality - observations") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            localTotal: 0,
            publicValues: [
                SpeciesObservationMonthCount(month: 7, count: 12),
                SpeciesObservationMonthCount(month: 8, count: 28),
                SpeciesObservationMonthCount(month: 9, count: 16)
            ],
            publicTotal: 56
        )
    )
    .padding()
}

#Preview("Seasonality - empty") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            localTotal: 0,
            publicValues: nil,
            publicTotal: nil
        )
    )
    .padding()
}
#endif
