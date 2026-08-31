import Foundation

enum SpeciesObservationChartTab: String, CaseIterable, Identifiable, Sendable {
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

struct SpeciesObservationMonthChartPoint: Identifiable, Sendable {
    let seriesName: String
    let month: Int
    let count: Int
    let normalizedCount: Double

    var id: String { "\(seriesName)-\(month)" }
    var hasObservations: Bool { count.signum() == 1 }
}

struct SpeciesObservationHistoryChartPoint: Identifiable, Sendable {
    let seriesName: String
    let date: Date
    let count: Int
    let normalizedCount: Double

    var id: String { "\(seriesName)-\(date.timeIntervalSince1970)" }
    var hasObservations: Bool { count.signum() == 1 }
}

enum SpeciesObservationChartPresentation {
    static func normalizedCategoryPoints(
        localSeries: [SpeciesObservationCategorySeries],
        publicSeries: [SpeciesObservationCategorySeries]
    ) -> [SpeciesObservationMonthChartPoint] {
        let local = localSeries.map { ("Local \($0.label)", $0.values) }
        let publicValues = publicSeries.map { ("Public \($0.label)", $0.values) }
        return normalizedMonthPoints(local + publicValues)
    }

    static func normalizedHistoryPoints(
        _ series: [(String, [SpeciesObservationHistoryCount])]
    ) -> [SpeciesObservationHistoryChartPoint] {
        series.flatMap { name, values in
            guard !values.isEmpty else {
                return [SpeciesObservationHistoryChartPoint]()
            }
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

    static func peakHistorySummary(
        name: String,
        values: [SpeciesObservationHistoryCount]
    ) -> String? {
        guard let peak = values.max(by: { $0.count < $1.count }),
              peak.hasObservations else {
            return nil
        }
        return "\(name) peak \(monthAbbreviation(for: peak.month)) \(peak.year): \(peak.count.formatted())"
    }

    static func topCategorySummary(
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

    static func joinedRawSummaries(_ summaries: [String?]) -> String? {
        let resolved = summaries.compactMap { $0 }
        return resolved.isEmpty ? nil : resolved.joined(separator: " · ")
    }

    static func monthAbbreviation(for month: Int) -> String {
        guard month >= 1 && month <= 12 else { return "" }
        return Calendar.current.shortMonthSymbols[month - 1]
    }

    private static func normalizedMonthPoints(
        _ series: [(String, [SpeciesObservationMonthCount])]
    ) -> [SpeciesObservationMonthChartPoint] {
        series.flatMap { name, values in
            guard !values.isEmpty else {
                return [SpeciesObservationMonthChartPoint]()
            }
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
            "peak \(SpeciesObservationChartPresentation.monthAbbreviation(for: peak.month)) \(peak.count.formatted())."
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
        let publicSeasonalityUnavailable = publicTotal > 0 && !publicHasMonthlyCounts

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
            detailLine: detailLine(for: cells),
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
            SpeciesObservationMonthCount(
                month: month,
                count: countsByMonth[month, default: 0]
            )
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

    private static func detailLine(
        for cells: [SpeciesSeasonalityHeatmapCell]
    ) -> String? {
        guard let peak = cells.max(by: { $0.count < $1.count }),
              peak.hasObservations else {
            return nil
        }

        let month = SpeciesObservationChartPresentation.monthAbbreviation(
            for: peak.month
        )
        return "Peak \(month): \(observationLabel(for: peak.count))"
    }

    private static func smoothedDisplayIntensities(
        _ rawIntensities: [Double]
    ) -> [Double] {
        guard rawIntensities.count == 12,
              rawIntensities.contains(where: { $0 > 0 }) else {
            return rawIntensities
        }

        return rawIntensities.indices.map { index in
            let neighborIntensity = rawIntensities.indices
                .map { observedIndex -> Double in
                    guard rawIntensities[observedIndex] > 0 else { return 0 }
                    let distance = cyclicDistance(
                        from: index,
                        to: observedIndex,
                        count: rawIntensities.count
                    )
                    return rawIntensities[observedIndex] * falloff(for: distance)
                }
                .max() ?? 0

            return max(rawIntensities[index], neighborIntensity)
        }
    }

    private static func cyclicDistance(
        from index: Int,
        to otherIndex: Int,
        count: Int
    ) -> Int {
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
